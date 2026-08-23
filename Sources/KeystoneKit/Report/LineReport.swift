import Foundation

/// One violation per line, in formats other tools already read.
///
/// This is the whole of what integrating with SwiftLint is worth. The two tools
/// overlap on a single rule, so there is nothing to delegate — but SwiftLint
/// has already taught every Swift developer's editor and CI how to read a
/// diagnostic, and matching that costs nothing. Findings then appear where
/// findings already appear: in Xcode's issue navigator, and against the changed
/// lines of a pull request.
public enum LineReport {
    public enum Format: String, Sendable {
        /// `path:line:col: severity: message (rule)` — what Xcode parses into
        /// inline warnings, and what SwiftLint prints by default.
        case xcode
        /// GitHub Actions workflow commands, which become annotations on the
        /// diff rather than a wall of log output nobody opens.
        case github
    }

    public static func render(_ result: CheckResult, format: Format) -> String {
        result.violations.map { violation in
            switch format {
            case .xcode: return xcode(violation)
            case .github: return github(violation)
            }
        }.joined(separator: "\n")
    }

    static func xcode(_ violation: Violation) -> String {
        let severity = violation.severity == .error ? "error" : "warning"
        // Columns are not tracked; a diagnostic without one is still parsed,
        // but the position has to be there for the line to be recognised.
        return "\(violation.file):\(violation.line ?? 1):1: \(severity): "
            + "\(violation.summary) (\(violation.rule))"
    }

    static func github(_ violation: Violation) -> String {
        let severity = violation.severity == .error ? "error" : "warning"
        var body = violation.summary
        if let fix = violation.fix { body += "\n\n" + fix }
        if let source = violation.source { body += "\n\n" + source }

        return "::\(severity) file=\(violation.file),line=\(violation.line ?? 1),"
            + "title=\(violation.rule)::\(escape(body))"
    }

    /// Workflow commands are newline-delimited, so a message containing one
    /// would be read as the end of the annotation and the start of a command.
    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
            .replacingOccurrences(of: ":", with: "%3A")
            .replacingOccurrences(of: ",", with: "%2C")
    }
}
