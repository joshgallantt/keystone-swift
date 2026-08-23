import Foundation

/// A layer should name things in its own language.
///
/// A protocol called `PaymentClient` declared in the domain is a domain service
/// wearing an infrastructure word. The domain's job is to say what the business
/// needs — that a payment is taken — not that something out there is a client of
/// something else. The name matters because it is what the next person reaches
/// for: once the domain contains a `Client`, an `API` and a `Cache`, nobody can
/// tell any more which of them are business rules.
///
/// A warning, because it is a judgement about wording rather than a structural
/// break, and because the alternative — refusing a write over a suffix — would
/// be tiresome enough to get the whole tool switched off.
public struct LayerVocabularyRule: Rule {
    public let identifier = "layer-vocabulary"
    public let defaultSeverity: Severity = .warning

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        var violations: [Violation] = []

        for file in context.files {
            guard let role = file.role, let definition = context.definition(for: role),
                  !definition.deniedNameSuffixes.isEmpty else { continue }

            // Protocols only, and that is what makes the rule safe to ship on
            // by default. A protocol named `*Client` in the domain is a service
            // that borrowed a word from the layer below it. A *struct* named
            // `Client` is an entity, and in a CRM, an agency's app or a law
            // firm's it is the most important noun the business has.
            for declaration in file.facts.declarations
            where declaration.isTopLevel && declaration.kind == .protocol {
                guard let suffix = definition.deniedNameSuffixes.first(where: {
                    declaration.name.hasSuffix($0) && declaration.name.count > $0.count
                }) else { continue }

                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: file.path,
                        line: declaration.line,
                        summary: "`\(declaration.name)` names a `\(suffix)` in `\(role)`, which borrows another "
                            + "layer's vocabulary",
                        fix: LayerVocabularyRule.advice(name: declaration.name, role: role, suffix: suffix),
                        source: Sources.ubiquitousLanguage
                    )
                )
            }
        }

        return violations
    }

    static func advice(name: String, role: Role, suffix: String) -> String {
        "If `\(name)` is a service the business needs — something taken, sent, checked or fetched on its "
        + "behalf — name it for what it does rather than for what it talks to, and leave the word "
        + "`\(suffix)` to the layer that owns the wire. A domain service says `TakePayment`; its "
        + "implementation over HTTP can be called whatever it likes. If this really is infrastructure "
        + "rather than a rule, then it is in the wrong layer and moving it is the fix, not renaming it."
    }
}
