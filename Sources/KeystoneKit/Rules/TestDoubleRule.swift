import Foundation

/// No two test doubles share a name.
///
/// A milder problem than it first looks. Swift already refuses two of the same
/// name in one module, so every duplicate this can find is in a different module
/// and cannot collide. What is left is a question of reading: two visible
/// `StubCatalog`s look like the same thing until you check. When every copy is
/// file-private the confusion is not even possible — but ten identical private
/// stubs still means the same double was written ten times, which is worth
/// saying in different words.
///
/// A warning either way. Repetition can never break a build, and calling it an
/// error is how a tool teaches people to stop reading its output.
///
/// This rule used to also require every double to live in a directory called
/// `Support/`, which was one folder name taken from one project and asserted
/// over everyone else's. It produced 705 findings across eight of thirty-two
/// apps, and the files it named were already properly isolated — in `Tests/Mocks/`,
/// `Tests/MockUseCases/`, `Tests/Doubles/`. A double kept apart from the suite
/// that uses it satisfies the reason the rule existed; which word the directory
/// uses for "apart" is not something a tool can be right about.
public struct TestDoubleRule: Rule {
    public let identifier = "doubles-are-uniquely-named"
    /// Repetition is never a correctness problem, so it never blocks.
    public let defaultSeverity: Severity = .warning
    public var needsWholeProject: Bool { true }

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        let tests = context.configuration.tests
        guard !tests.isEmpty else { return [] }

        var violations: [Violation] = []
        var byName: [String: [(file: String, line: Int, visible: Bool)]] = [:]

        // Both roles. Filtering on `.tests` alone is how this rule went blind:
        // the moment a project took the advice and moved its doubles into a
        // shared module, they stopped being test files and the check for
        // duplicates stopped seeing them.
        for file in context.files where file.role?.isTestFacing == true {
            for declaration in file.facts.declarations
            where declaration.isTopLevel && declaration.isNominalType && tests.isDouble(declaration.name) {
                byName[declaration.name, default: []].append(
                    (file.path, declaration.line, declaration.accessLevel > .fileprivate)
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
                    rule: identifier,
                    severity: defaultSeverity,
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
