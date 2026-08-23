import Foundation

/// The dependency rule for codebases that have no modules yet.
///
/// Most iOS apps are one target with folders. There are no imports to check,
/// so an import-based tool would report a clean bill of health on a codebase
/// with no boundaries at all. Type references are the evidence that survives:
/// a file in the presentation folder naming a type declared in the data folder
/// has crossed the boundary whether or not the compiler noticed.
///
/// Deliberately narrow. Only references *inside a single module* are judged,
/// because anything crossing a module is already the import rule's business,
/// and a name more than one module declares is skipped rather than guessed at.
public struct TypeReferenceBoundaryRule: Rule {
    public let identifier = "type-reference-boundary"
    public let defaultSeverity: Severity = .error
    public var needsWholeProject: Bool { true }

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        let advisor = DestinationAdvisor(configuration: context.configuration)
        var violations: [Violation] = []

        for file in context.files {
            guard let role = file.role, let definition = context.definition(for: role) else { continue }
            let scope = file.module?.name

            let declaredHere = Set(file.facts.declarations.map(\.name))

            for reference in file.facts.typeReferences {
                guard !declaredHere.contains(reference.name),
                      !context.symbols.isAmbiguous(reference.name),
                      context.symbols.declaringScopes(of: reference.name) == [scope],
                      let declaringRole = context.symbols.declaringRole(of: reference.name),
                      declaringRole != role
                else { continue }

                let verdict = context.permits(
                    from: role,
                    to: declaringRole,
                    fromPackage: file.module?.packageDirectory,
                    toPackage: file.module?.packageDirectory
                )
                guard verdict != .permitted else { continue }

                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: file.path,
                        line: reference.line,
                        summary: "`\(role)` uses `\(reference.name)`, which `\(declaringRole)` declares",
                        fix: BoundaryPhrasing.invert(
                            role: role,
                            definition: definition,
                            towards: declaringRole,
                            file: file.path,
                            advisor: advisor
                        )
                        + " These two layers are in one module today, so nothing stops this at compile time — "
                        + "which is exactly why it is worth fixing before they are split apart.",
                        source: Sources.dependencyRule
                    )
                )
            }
        }

        return violations
    }
}
