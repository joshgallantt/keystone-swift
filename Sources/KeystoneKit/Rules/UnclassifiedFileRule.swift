import Foundation

/// Every Swift file must belong to a layer, or be excluded on purpose.
///
/// Silence is the failure mode of every architecture checker: a file no rule
/// claims passes every rule, and a project can be entirely "clean" while most
/// of it is unexamined. This rule makes the gap visible, and during a migration
/// it is the progress bar — the number falls as layers are described, and when
/// it reaches zero the tool is finally looking at the whole codebase.
public struct UnclassifiedFileRule: Rule {
    public let identifier = "unclassified-files"
    public let defaultSeverity: Severity = .warning
    public var needsWholeProject: Bool { true }

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        context.files
            .filter { $0.role == nil }
            .map { file in
                Violation(
                    rule: identifier,
                    severity: defaultSeverity,
                    file: file.path,
                    line: nil,
                    summary: "No layer claims this file, so no rule examined it",
                    fix: "Add this directory to a role's `paths` in the configuration, or to `exclude` if it is "
                        + "deliberately outside the architecture. Until then the tool reports it as clean without "
                        + "having checked anything about it.",
                    source: nil
                )
            }
    }
}
