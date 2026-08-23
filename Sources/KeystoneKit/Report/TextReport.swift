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
        for rule in grouped.keys.sorted() {
            let violations = grouped[rule]!.sortedForReport()
            let worst = violations.contains { $0.severity == .error } ? Severity.error : .warning
            out.append(heading(rule: rule, count: violations.count, severity: worst))
            out.append("")

            for violation in violations {
                out.append(contentsOf: entry(violation))
            }
        }

        out.append(summary(result, baselined: baselined, scoped: scoped))
        return out.joined(separator: "\n") + "\n"
    }

    private func heading(rule: String, count: Int, severity: Severity) -> String {
        let mark = severity == .error ? "✗" : "!"
        let noun = count == 1 ? "violation" : "violations"
        let text = "\(mark) \(rule)  \(count) \(noun)"
        return paint(text, severity == .error ? .red : .yellow, bold: true)
    }

    private func entry(_ violation: Violation) -> [String] {
        var lines: [String] = []
        let where_ = violation.line.map { "\(violation.file):\($0)" } ?? violation.file

        lines.append("  " + paint(where_, .cyan))
        lines.append("    " + violation.summary)

        if let fix = violation.fix {
            lines.append("")
            lines.append(contentsOf: wrap(fix, indent: "    "))
        }
        if let source = violation.source {
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
