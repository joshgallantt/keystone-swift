import Foundation

/// Test doubles live in `Support/`, and no two of them share a name.
///
/// The prefixes come from Meszaros' taxonomy, which Fowler's *Mocks Aren't
/// Stubs* made the common vocabulary: a stub answers, a spy records, a mock
/// expects, a fake works. Keeping the kind in the name is not decoration — it
/// tells the reader whether the test that follows verifies state or behaviour.
///
/// Duplicate names are a separate problem, and a milder one than it first
/// looks. Swift already refuses two of the same name in one module, so every
/// duplicate this can find is in a different module and cannot collide. What is
/// left is a question of reading: two visible `StubCatalog`s look like the same
/// thing until you check. When every copy is file-private the confusion is not
/// even possible — but ten identical private stubs still means the same double
/// was written ten times, which is worth saying in different words.
///
/// A warning either way. Neither case can break a build, and calling repetition
/// an error is how a tool teaches people to stop reading its output.
public struct TestDoubleRule: Rule {
    public let identifier = "doubles-live-in-support"
    public var emittedIdentifiers: [String] { [identifier, "doubles-are-uniquely-named"] }
    public let defaultSeverity: Severity = .error
    /// Repetition is never a correctness problem, so it never blocks.
    static let duplicateSeverity: Severity = .warning
    public var needsWholeProject: Bool { true }

    public init() {}

    public func defaultSeverity(for identifier: String) -> Severity {
        identifier == "doubles-are-uniquely-named" ? TestDoubleRule.duplicateSeverity : defaultSeverity
    }

    public func evaluate(_ context: RuleContext) -> [Violation] {
        let tests = context.configuration.tests
        guard !tests.isEmpty else { return [] }

        var violations: [Violation] = []
        var byName: [String: [(file: String, line: Int, visible: Bool)]] = [:]

        // Both roles. Filtering on `.tests` alone is how this rule went blind:
        // the moment a project took the advice and moved its doubles into a
        // shared module, they stopped being test files and the check for
        // duplicates stopped seeing them. Three duplicates then accumulated in
        // silence under a clean report, which is worse than never having had
        // the rule.
        for file in context.files where file.role?.isTestFacing == true {
            for declaration in file.facts.declarations
            where declaration.isTopLevel && declaration.isNominalType && tests.isDouble(declaration.name) {
                byName[declaration.name, default: []].append(
                    (file.path, declaration.line, declaration.accessLevel > .fileprivate)
                )

                // Already in a shared module, which is a stronger form of the
                // same thing this rule asks for.
                guard file.role != .testSupport, !tests.isSupport(file.path) else { continue }
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
            let anyVisible = sites.contains { $0.visible }

            violations.append(
                Violation(
                    rule: "doubles-are-uniquely-named",
                    severity: TestDoubleRule.duplicateSeverity,
                    file: sites[0].file,
                    line: sites[0].line,
                    summary: anyVisible
                        ? "`\(name)` is declared \(sites.count) times, also in \(others)"
                        : "`\(name)` is written \(sites.count) times over, each one file-private, also in "
                            + "\(others)",
                    fix: anyVisible
                        ? "Give each a name saying which collaborator it stands in for, or keep one and "
                            + "share it. Two doubles with the same name read as the same thing until "
                            + "somebody checks, and the second one usually exists because whoever wrote it "
                            + "could not find the first."
                        : "Nothing can collide here — each copy is private to its own file, in its own "
                            + "module — so this is not a naming problem but a repetition one. The same "
                            + "double has been written \(sites.count) times, which means these suites share "
                            + "a need that nothing in the project expresses. Either accept the copies as "
                            + "the price of keeping the test targets independent, which is a reasonable "
                            + "trade, or give that need a home they can all depend on.",
                    source: Sources.testDoubles
                )
            )
        }

        return violations
    }
}
