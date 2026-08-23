import Foundation

/// A file in a tier declares tests. A file in `Support/` declares none.
///
/// This is the split every other testing rule rests on. Without it there is no
/// way to ask whether a suite actually asserts anything, or whether a helper
/// has quietly grown assertions of its own — the target is just a bag of files.
/// With it, both halves become checkable, and a driver stops being mistaken for
/// coverage.
public struct TestSupportRule: Rule {
    public let identifier = "support-separation"
    public var emittedIdentifiers: [String] { [identifier, "tests-assert-something"] }
    public let defaultSeverity: Severity = .error

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        let tests = context.configuration.tests
        guard !tests.isEmpty else { return [] }

        var violations: [Violation] = []

        for file in context.files {
            guard file.role == .tests, let tier = tests.tier(forFile: file.path) else { continue }
            let isSupport = tests.isSupport(file.path)
            let declaresTests = !file.facts.tests.isEmpty

            if isSupport && declaresTests {
                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: file.path,
                        line: file.facts.tests.first?.line,
                        summary: "`\(tests.supportDirectory)/` holds a test, which belongs beside the others",
                        fix: "Move this test up into the `\(tier.name)` suite itself and leave only helpers "
                            + "here. A test hidden among the scaffolding is one nobody reads when the suite "
                            + "is reviewed, and one nobody notices when it stops asserting anything.",
                        source: Sources.testBoundary
                    )
                )
                continue
            }

            if !isSupport && !declaresTests {
                violations.append(
                    Violation(
                        rule: "tests-assert-something",
                        severity: defaultSeverity,
                        file: file.path,
                        line: nil,
                        summary: "This file is in the `\(tier.name)` suite but declares no tests",
                        fix: "Either it is a test and should declare one, or it is a driver, a double or a "
                            + "builder — in which case move it to `\(tests.supportDirectory)/` beside the "
                            + "suite it serves. Helper code counted as a test file is how a suite comes to "
                            + "look larger than it is.",
                        source: Sources.testBoundary
                    )
                )
            }
        }

        return violations
    }
}
