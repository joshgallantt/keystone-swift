import Foundation

/// An extension must be doing one of the two jobs only an extension can do.
///
/// Swift needs extensions for two things: declaring a conformance, and giving a
/// protocol a default implementation. Everything else an extension is used for
/// — a convenience property here, a formatting helper there — splits a type's
/// surface across the file system. The type's real shape is then whatever the
/// union of its extensions happens to be, which no single file states and no
/// reader can see, and which differs by module depending on what is imported.
///
/// Tests are exempt. A test file's extensions are scaffolding for one suite and
/// do not travel, which is the whole reason the objection does not apply.
public struct ExtensionPolicyRule: Rule {
    public let identifier = "no-extensions"
    public let defaultSeverity: Severity = .error
    public var needsWholeProject: Bool { true }

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        var violations: [Violation] = []

        for file in context.files {
            guard let role = file.role, role != .tests else { continue }

            for declaration in file.facts.extensions {
                // Declaring a conformance. Swift offers no other way to adopt a
                // protocol after the fact, so this is not a choice being made.
                if !declaration.inheritedTypes.isEmpty { continue }

                // A default implementation hung off a protocol. The members
                // belong to the protocol, which is a single place, so the
                // objection above does not apply.
                if ExtensionPolicyRule.extendsProtocol(declaration.name, in: context) { continue }

                // A member available only under a constraint cannot be written
                // in the type's body. Swift requires the extension, so there is
                // no decision here to disagree with.
                if declaration.isConstrained { continue }

                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: file.path,
                        line: declaration.line,
                        summary: "`extension \(declaration.name)` adds members without declaring a conformance",
                        fix: "Move these members into `\(declaration.name)` itself, so the type has one "
                            + "definition and one shape. An extension is for adopting a protocol, or for "
                            + "giving a protocol a default implementation; used for anything else it scatters "
                            + "the type across files, and what the type can do becomes whatever the union of "
                            + "its extensions happens to be. If these members belong to this layer rather than "
                            + "to the type, they want a type of their own here instead.",
                        source: Sources.singleResponsibility
                    )
                )
            }
        }

        return violations
    }
}

extension ExtensionPolicyRule {
    /// Whether the extended name is a protocol.
    ///
    /// The project's own declarations are known exactly. For anything else the
    /// platform list is consulted, because `extension View` is how a SwiftUI
    /// modifier is written and is a protocol extension like any other — while
    /// `extension String` is a concrete type belonging to somebody else, which
    /// is the case this rule exists for. Not knowing is treated as "not a
    /// protocol", so the answer errs toward reporting.
    static func extendsProtocol(_ name: String, in context: RuleContext) -> Bool {
        let declarations = context.symbols.declarations(of: name)
        if declarations.isEmpty { return PlatformProtocols.contains(name) }
        return declarations.allSatisfy { $0.kind == .protocol }
    }
}
