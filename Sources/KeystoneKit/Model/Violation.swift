import Foundation

public enum Severity: String, Codable, Sendable, Comparable {
    case warning
    case error

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs == .warning && rhs == .error
    }
}

/// One thing that is wrong, and enough to act on it without opening a manual.
///
/// `summary` says what happened, `fix` says what to do instead. The split is
/// deliberate: an agent that is told only what it broke will guess at the
/// remedy, and a guess that compiles is the most expensive kind of wrong.
public struct Violation: Sendable, Codable, Hashable {
    public var rule: String
    public var severity: Severity
    public var file: String
    public var line: Int?
    public var summary: String
    public var fix: String?
    public var source: String?

    public init(
        rule: String,
        severity: Severity,
        file: String,
        line: Int? = nil,
        summary: String,
        fix: String? = nil,
        source: String? = nil
    ) {
        self.rule = rule
        self.severity = severity
        self.file = file
        self.line = line
        self.summary = summary
        self.fix = fix
        self.source = source
    }
}

extension Array where Element == Violation {
    /// A total order, so the same project always reports in the same sequence.
    /// Determinism is the product; an unstable sort would leak nondeterminism
    /// into every diff of a report.
    public func sortedForReport() -> [Violation] {
        sorted { left, right in
            if left.file != right.file { return left.file < right.file }
            if (left.line ?? 0) != (right.line ?? 0) { return (left.line ?? 0) < (right.line ?? 0) }
            if left.rule != right.rule { return left.rule < right.rule }
            return left.summary < right.summary
        }
    }

    public var errors: [Violation] { filter { $0.severity == .error } }
    public var warnings: [Violation] { filter { $0.severity == .warning } }
}
