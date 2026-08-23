import Foundation

/// Work recorded where nobody will look for it.
///
/// The lowest-stakes rule here, and the one most likely to be switched off,
/// which is fine — it is a warning and it says so. It earns its place during a
/// migration, where a `TODO` is usually the note somebody left instead of
/// moving the file.
public struct TodoCommentRule: Rule {
    public let identifier = "no-todo"
    public let defaultSeverity: Severity = .warning

    static let markers = ["TODO", "FIXME", "HACK", "XXX"]

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        var violations: [Violation] = []

        for file in context.files {
            for comment in file.facts.comments {
                guard let marker = TodoCommentRule.marker(in: comment.text) else { continue }
                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: file.path,
                        line: comment.line,
                        summary: "`\(marker)` comment",
                        fix: "Do the work, or delete the code and record the intent where the team will see it. "
                            + "A tracked issue outlives a comment; a comment outlives the reason for it.",
                        source: nil
                    )
                )
            }
        }

        return violations
    }

    static func marker(in text: String) -> String? {
        for marker in markers {
            guard let range = text.range(of: marker) else { continue }
            // Word boundary on the left, so `AUTODOC` is not a `TODO`.
            let precedingIsLetter = range.lowerBound > text.startIndex
                && (text[text.index(before: range.lowerBound)].isLetter
                    || text[text.index(before: range.lowerBound)].isNumber)
            if !precedingIsLetter { return marker }
        }
        return nil
    }
}
