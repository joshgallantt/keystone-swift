import Foundation

/// The report a person reads.
///
/// Grouped by rule rather than by file, because during a migration the useful
/// question is "what kind of thing is wrong here" — twelve misplaced view
/// models are one afternoon's work, while one dependency cycle is a design
/// conversation. Every entry ends with the correction and its source, so the
/// report can be acted on top to bottom without opening anything else.
public struct TextReport: Sendable {
    public var width: Int
    public var colour: Bool

    public init(width: Int = 92, colour: Bool = false) {
        self.width = width
        self.colour = colour
    }

    /// `scoped` is true when only part of the project was reported on, which
    /// changes what the closing line is allowed to claim. "332 files, no
    /// violations" after checking five of them is a sentence that reads as an
    /// all-clear the run never established.
    public func render(_ result: CheckResult, baselined: Int = 0, scoped: Bool = false) -> String {
        var out: [String] = []

        let grouped = Dictionary(grouping: result.violations, by: \.rule)
        for rule in TextReport.reportOrder(of: Array(grouped.keys)) {
            let violations = grouped[rule]!.sortedForReport()
            let worst = violations.contains { $0.severity == .error } ? Severity.error : .warning
            let claims = TextReport.claims(in: violations)
            out.append(heading(rule: rule, count: violations.count, distinct: claims.count, severity: worst))
            out.append("")

            for claim in claims {
                out.append(contentsOf: entry(claim))
            }
        }

        out.append(summary(result, baselined: baselined, scoped: scoped))
        return out.joined(separator: "\n") + "\n"
    }

    private func heading(rule: String, count: Int, distinct: Int, severity: Severity) -> String {
        let mark = severity == .error ? "✗" : "!"
        let noun = count == 1 ? "violation" : "violations"
        var text = "\(mark) \(rule)  \(count) \(noun)"
        // A rule that says one thing 2,805 times has found one thing. Saying so
        // in the heading is the difference between a reader who reads on and a
        // reader who scrolls.
        if distinct < count { text += "  ·  \(distinct) distinct" }
        return paint(text, severity == .error ? .red : .yellow, bold: true)
    }

    /// The order rules were declared in, which runs boundaries first and style
    /// last. Alphabetical order opened every report on whichever identifier
    /// happened to sort first.
    static func reportOrder(of rules: [String]) -> [String] {
        let declared = RuleRegistry.identifiers
        return rules.sorted { a, b in
            let ia = declared.firstIndex(of: a) ?? declared.count
            let ib = declared.firstIndex(of: b) ?? declared.count
            return ia == ib ? a < b : ia < ib
        }
    }

    /// One entry per distinct thing said, with the places it was said about.
    ///
    /// Findings that share a rule, a sentence, a correction and a citation are
    /// one finding reported many times. Across thirty-two apps the tool printed
    /// 15,503 entries carrying 3,872 distinct sentences; `test-tiers` alone
    /// printed one sentence 2,805 times.
    static func claims(in violations: [Violation]) -> [Claim] {
        var order: [String] = []
        var byKey: [String: Claim] = [:]

        for violation in violations {
            let key = [violation.summary, violation.fix ?? "", violation.source ?? ""].joined(separator: "\u{1}")
            if byKey[key] == nil {
                order.append(key)
                byKey[key] = Claim(
                    summary: violation.summary,
                    fix: violation.fix,
                    source: violation.source,
                    locations: []
                )
            }
            byKey[key]!.locations.append(Location(file: violation.file, line: violation.line))
        }

        return order.compactMap { byKey[$0] }
    }

    struct Location: Sendable {
        var file: String
        var line: Int?
    }

    struct Claim: Sendable {
        var summary: String
        var fix: String?
        var source: String?
        var locations: [Location]
    }

    /// How many files a repeated claim names before the rest are counted.
    /// Every location stays in `--reporter json`, `--reporter xcode` and the
    /// baseline; this is the terminal being readable, not the tool forgetting.
    static let filesShown = 8

    private func entry(_ claim: Claim) -> [String] {
        var lines: [String] = []

        // Locations folded per file, so a claim about eleven lines of one file
        // reads as one file.
        var order: [String] = []
        var linesByFile: [String: [Int]] = [:]
        for location in claim.locations {
            if linesByFile[location.file] == nil { order.append(location.file); linesByFile[location.file] = [] }
            if let line = location.line { linesByFile[location.file]!.append(line) }
        }

        if claim.locations.count > 1 {
            lines.append("  " + claim.summary + paint("  ×\(claim.locations.count)", .dim))
        }

        for file in order.prefix(TextReport.filesShown) {
            let numbers = linesByFile[file]!.sorted()
            let suffix: String
            switch numbers.count {
            case 0: suffix = ""
            case 1: suffix = ":\(numbers[0])"
            default: suffix = ":" + numbers.map(String.init).joined(separator: ", :")
            }
            lines.append("  " + paint(file + suffix, .cyan))
        }
        if order.count > TextReport.filesShown {
            let rest = order.count - TextReport.filesShown
            lines.append("  " + paint("… and \(rest) more \(rest == 1 ? "file" : "files")", .dim))
        }

        if claim.locations.count == 1 {
            lines.append("    " + claim.summary)
        }

        if let fix = claim.fix {
            lines.append("")
            lines.append(contentsOf: wrap(fix, indent: "    "))
        }
        if let source = claim.source {
            lines.append("")
            lines.append(contentsOf: wrap(source, indent: "    ").map { paint($0, .dim) })
        }
        lines.append("")
        return lines
    }

    private func summary(_ result: CheckResult, baselined: Int, scoped: Bool) -> String {
        let errors = result.errors.count
        let warnings = result.warnings.count

        if errors == 0 && warnings == 0 && baselined == 0 {
            return scoped
                ? paint("✓ no violations", .green)
                : paint("✓ \(count(result.filesChecked, "file")), no violations", .green)
        }

        var parts: [String] = []
        if errors > 0 { parts.append(paint("\(errors) \(errors == 1 ? "error" : "errors")", .red)) }
        if warnings > 0 { parts.append(paint("\(warnings) \(warnings == 1 ? "warning" : "warnings")", .yellow)) }
        if parts.isEmpty { parts.append(paint("no new violations", .green)) }

        var line = parts.joined(separator: ", ")
        if !scoped { line += " in \(count(result.filesChecked, "file"))" }
        if baselined > 0 {
            line += paint("  ·  \(baselined) already accepted as existing debt", .dim)
        }
        return line
    }

    private func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(noun)\(number == 1 ? "" : "s")"
    }

    // MARK: - Presentation

    private enum Colour: String {
        case red = "31"
        case green = "32"
        case yellow = "33"
        case cyan = "36"
        case dim = "2"
    }

    private func paint(_ text: String, _ colour: Colour, bold: Bool = false) -> String {
        guard self.colour else { return text }
        let prefix = bold ? "\u{1B}[1;\(colour.rawValue)m" : "\u{1B}[\(colour.rawValue)m"
        return prefix + text + "\u{1B}[0m"
    }

    /// Wrapping is done here rather than left to the terminal so that a fix
    /// which runs to three sentences stays readable when it is piped into a
    /// file, a pull request comment, or an agent's context.
    func wrap(_ text: String, indent: String) -> [String] {
        let limit = max(20, width - indent.count)
        var lines: [String] = []

        for paragraph in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var current = ""
            for word in paragraph.split(separator: " ") {
                if current.isEmpty {
                    current = String(word)
                } else if current.count + 1 + word.count <= limit {
                    current += " " + word
                } else {
                    lines.append(indent + current)
                    current = String(word)
                }
            }
            lines.append(indent + current)
        }

        return lines
    }
}
