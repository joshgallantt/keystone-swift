import Foundation

/// A business-facing suite speaks the business's language and no other.
///
/// The point of an acceptance tier is that the feature can be rearranged
/// underneath it without the suite being touched. The moment a test names a
/// repository or a DTO, that stops being true: the suite is now coupled to the
/// arrangement rather than to the behaviour, and every refactor breaks tests
/// that were supposed to prove the refactor was safe.
///
/// Stated between roles rather than over names, which matters more than it
/// looks: a project whose business genuinely involves a `Store`, an `Account` or a
/// `Client` may name its driver after one. A pattern over those words would ban
/// the domain's own vocabulary from the suite meant to speak it; a rule phrased
/// over roles bans only what the data layer actually declared.
public struct AcceptanceVocabularyRule: Rule {
    public let identifier = "acceptance-vocabulary"
    public let defaultSeverity: Severity = .error
    public var needsWholeProject: Bool { true }

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        let tests = context.configuration.tests
        guard !tests.isEmpty else { return [] }

        var violations: [Violation] = []

        for file in context.files where file.role == .tests {
            guard let tier = tests.tier(forFile: file.path),
                  !tier.mayNotReference.isEmpty,
                  // Support code is where the concrete types are supposed to
                  // be named — that is what a driver is for.
                  !tests.isSupport(file.path) else { continue }

            let declaredHere = Set(file.facts.declarations.map(\.name))

            for reference in file.facts.typeReferences {
                guard !declaredHere.contains(reference.name),
                      !context.symbols.isAmbiguous(reference.name),
                      let declaringRole = context.symbols.declaringRole(of: reference.name),
                      tier.mayNotReference.contains(declaringRole) else { continue }

                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: file.path,
                        line: reference.line,
                        summary: "The `\(tier.name)` suite names `\(reference.name)`, which `\(declaringRole)` "
                            + "declares",
                        fix: tier.reason ?? (
                            "Drive the feature through the tier's own vocabulary instead — the driver in "
                            + "`\(tests.supportDirectory)/` exists so that this suite never has to know how "
                            + "the feature is put together. Naming `\(reference.name)` here couples the test "
                            + "to today's arrangement, so tomorrow's refactor breaks the very suite that was "
                            + "meant to prove it safe. If the driver cannot express what this test needs, "
                            + "the driver is what to extend."
                        ),
                        source: Sources.testBoundary
                    )
                )
            }
        }

        return violations
    }
}
