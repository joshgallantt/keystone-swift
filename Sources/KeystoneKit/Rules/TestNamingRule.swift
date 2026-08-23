import Foundation

/// A business-facing test is named in a sentence.
///
/// This is the half of Cucumber worth keeping. A `.feature` file buys a
/// readable sentence at the cost of an indirection between the sentence and the
/// code; a display name on the test itself buys the same sentence with none.
/// buys the same sentence with none. What it does not buy on its own is the
/// discipline — hence this rule, which a Gherkin runner would not have given
/// you either, since it would happily execute a feature file full of
/// `FakeCatalog`.
public struct TestNamingRule: Rule {
    public let identifier = "test-names-read-as-prose"
    public let defaultSeverity: Severity = .error

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        let tests = context.configuration.tests
        guard !tests.isEmpty else { return [] }

        var violations: [Violation] = []

        for file in context.files where file.role == .tests {
            guard let tier = tests.tier(forFile: file.path), tier.namesReadAsProse,
                  !tests.isSupport(file.path) else { continue }

            for test in file.facts.tests {
                guard !TestNamingRule.readsAsProse(test) else { continue }

                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: file.path,
                        line: test.line,
                        summary: test.displayName == nil
                            ? "`\(test.functionName)` has no sentence for a name"
                            : "`\(test.displayName!)` is an identifier rather than a sentence",
                        fix: "Give it a display name shaped like `@Test(\"Someone who <does this> <ends up "
                            + "with that>\")` — a sentence a person who has not read the code could check "
                            + "against what the software is supposed to do. A `\(tier.name)` failure has to "
                            + "say what was lost, not which function returned the wrong value.",
                        source: Sources.acceptanceTests
                    )
                )
            }
        }

        return violations
    }

    /// A sentence has spaces in it. Deliberately the whole test: anything
    /// stricter starts arguing about grammar, and anything looser accepts
    /// `testBagFlow2` with a display name attached.
    static func readsAsProse(_ test: TestDeclaration) -> Bool {
        guard let name = test.displayName else { return false }
        return name.contains(" ")
    }
}
