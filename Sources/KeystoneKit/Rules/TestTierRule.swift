import Foundation

/// Every test file belongs to one of the declared tiers.
///
/// A test target that is neither an acceptance suite nor a unit suite is a
/// third thing nobody named, and third things are where layer tests and
/// integration tests accumulate — suites that break for reasons unrelated to
/// any rule, and which get disabled rather than fixed. A new behaviour is a new
/// journey in an existing acceptance suite or a new case in an existing unit
/// suite, not a new kind of test.
public struct TestTierRule: Rule {
    public let identifier = "test-tiers"
    public let defaultSeverity: Severity = .error

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        let tests = context.configuration.tests
        guard !tests.isEmpty else { return [] }

        return context.files.compactMap { file in
            guard file.role == .tests, tests.tier(forFile: file.path) == nil else { return nil }

            let names = tests.tiers.map { "`\($0.name)`" }.joined(separator: " or ")
            return Violation(
                rule: identifier,
                severity: defaultSeverity,
                file: file.path,
                line: nil,
                summary: "This test file belongs to no declared tier",
                fix: "Move it into the \(names) suite for its package. Every test answers one of two "
                    + "questions — whether the feature works, in the language of the business, or whether a "
                    + "unit is correct, in the language of the system — and a file that answers neither "
                    + "will be the first one somebody disables.",
                source: Sources.testBoundary
            )
        }
    }
}
