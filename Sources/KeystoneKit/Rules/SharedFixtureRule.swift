import Foundation

/// No file of shared test data.
///
/// In Meszaros' vocabulary a *fixture* is the state a test sets up, and a
/// **shared fixture** is listed as a cause of erratic, interacting tests: every
/// test comes to depend on data no test owns, and the first person to adjust it
/// for their case breaks three others who never knew they were reading it.
///
/// The replacement is a test data builder: a small type per thing the tests
/// need, where each test sets only the field it cares about and inherits
/// sensible values for the rest.
public struct SharedFixtureRule: Rule {
    public let identifier = "no-shared-fixtures"
    public let defaultSeverity: Severity = .warning

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        let tests = context.configuration.tests
        guard !tests.isEmpty else { return [] }

        return context.files.compactMap { file in
            guard file.role == .tests else { return nil }
            let name = Paths.lastComponent(of: file.path).replacingOccurrences(of: ".swift", with: "")
            guard tests.sharedFixtureNames.contains(name) else { return nil }

            return Violation(
                rule: identifier,
                severity: defaultSeverity,
                file: file.path,
                line: nil,
                summary: "`\(name).swift` is a shared fixture",
                fix: "Replace it with test data builders: one small type per thing the tests need, where "
                    + "each test sets only the field it cares about and inherits the rest. Shared data is "
                    + "owned by "
                    + "no test, so nobody can change it safely and everybody reads it; the tests that break "
                    + "when it changes are never the ones being edited.",
                source: Sources.testDataBuilder
            )
        }
    }
}
