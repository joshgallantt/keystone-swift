import Foundation

/// Test doubles live in `Support/`, and no two of them share a name.
///
/// The prefixes come from Meszaros' taxonomy, which Fowler's *Mocks Aren't
/// Stubs* made the common vocabulary: a stub answers, a spy records, a mock
/// expects, a fake works. Keeping the kind in the name is not decoration — it
/// tells the reader whether the test that follows verifies state or behaviour.
///
/// Duplicate names are a separate problem. Two `StubCatalog`s in one repository
/// look interchangeable in a review and are not, and the second one exists
/// because whoever wrote it could not find the first.
public struct TestDoubleRule: Rule {
    public let identifier = "doubles-live-in-support"
    public var emittedIdentifiers: [String] { [identifier, "doubles-are-uniquely-named"] }
    public let defaultSeverity: Severity = .error
    public var needsWholeProject: Bool { true }

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        let tests = context.configuration.tests
        guard !tests.isEmpty else { return [] }

        var violations: [Violation] = []
        var byName: [String: [(file: String, line: Int)]] = [:]

        for file in context.files where file.role == .tests {
            for declaration in file.facts.declarations
            where declaration.isTopLevel && declaration.isNominalType && tests.isDouble(declaration.name) {
                byName[declaration.name, default: []].append((file.path, declaration.line))

                guard !tests.isSupport(file.path) else { continue }
                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: file.path,
                        line: declaration.line,
                        summary: "`\(declaration.name)` is a test double declared outside "
                            + "`\(tests.supportDirectory)/`",
                        fix: "Move it to `\(tests.supportDirectory)/` beside the suite that uses it. Doubles "
                            + "declared among the tests get copied rather than found, which is how a "
                            + "repository ends up with four stubs for the same collaborator, each slightly "
                            + "different.",
                        source: Sources.testDoubles
                    )
                )
            }
        }

        for name in byName.keys.sorted() {
            let sites = byName[name]!.sorted { $0.file < $1.file }
            guard sites.count > 1 else { continue }
            let others = sites.dropFirst().map(\.file).joined(separator: ", ")
            violations.append(
                Violation(
                    rule: "doubles-are-uniquely-named",
                    severity: defaultSeverity,
                    file: sites[0].file,
                    line: sites[0].line,
                    summary: "`\(name)` is declared \(sites.count) times, also in \(others)",
                    fix: "Give each one a name that says which collaborator it stands in for, or keep one "
                        + "and share it. Two doubles with the same name read as the same thing in a review "
                        + "and behave differently in the run, which is the most expensive kind of "
                        + "disagreement a test suite can contain.",
                    source: Sources.testDoubles
                )
            )
        }

        return violations
    }
}
