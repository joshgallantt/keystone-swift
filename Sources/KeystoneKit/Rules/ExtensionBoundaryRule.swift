import Foundation

/// One layer may not reopen another layer's types.
///
/// An extension gives a type a different surface depending on which module is
/// reading it: a member exists on `Order` in the package that added it and
/// silently does not in the package next door, which then grows its own copy of
/// the same rule. The remedy is a presentation model — a type the screen owns,
/// mapped from the domain type at the boundary.
///
/// Stated between roles rather than between type names, so it holds in a
/// codebase this tool has never seen.
public struct ExtensionBoundaryRule: Rule {
    public let identifier = "extension-boundary"
    public let defaultSeverity: Severity = .error
    public var needsWholeProject: Bool { true }

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        var violations: [Violation] = []

        for file in context.files {
            guard let role = file.role else { continue }

            let boundaries = context.configuration.extensionBoundaries.filter { $0.from.contains(role) }
            guard !boundaries.isEmpty else { continue }

            for declaration in file.facts.extensions {
                // Extending a type the same module declared is ordinary code
                // organisation, not a boundary crossing.
                if context.symbols.declaringScopes(of: declaration.name) == [file.module?.name] {
                    continue
                }
                guard !context.symbols.isAmbiguous(declaration.name),
                      let declaringRole = context.symbols.declaringRole(of: declaration.name),
                      declaringRole != role else { continue }

                guard let boundary = boundaries.first(where: { $0.declaredIn.contains(declaringRole) }) else { continue }

                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: file.path,
                        line: declaration.line,
                        summary: "`\(role)` extends `\(declaration.name)`, a type `\(declaringRole)` declares",
                        fix: boundary.reason ?? (
                            "Adding members to `\(declaration.name)` from here means the type has one shape in "
                            + "`\(declaringRole)` and another in `\(role)`, and the next module along will grow its "
                            + "own copy of whatever you just added. Build a type this layer owns instead: a struct "
                            + "of already-prepared values, mapped from `\(declaration.name)` by an initialiser in "
                            + "its own body."
                        ),
                        source: Sources.humbleObject
                    )
                )
            }
        }

        return violations
    }
}
