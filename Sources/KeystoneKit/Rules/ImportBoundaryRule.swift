import Foundation

/// The dependency rule, read from `import` statements.
///
/// This is the rule every other boundary rule is a special case of: source
/// code dependencies point inward, and each layer states how far in it is
/// allowed to reach. It runs per file, which is what lets it answer before an
/// agent's write lands rather than after CI has already gone red.
public struct ImportBoundaryRule: Rule {
    public let identifier = "dependency-rule"
    public var emittedIdentifiers: [String] { [identifier, "feature-isolation", "not-visible"] }
    public let defaultSeverity: Severity = .error

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        let advisor = DestinationAdvisor(configuration: context.configuration)
        var violations: [Violation] = []

        for file in context.files {
            guard let role = file.role, let definition = context.definition(for: role) else { continue }

            for reference in file.facts.imports {
                guard reference.module != file.module?.name else { continue }

                // Imports name modules, never products. A product is a
                // packaging decision; only the module is a thing the compiler
                // will let you write `import` for.
                guard let imported = context.graph.modules[reference.module],
                      let importedRole = context.assignment.role(ofModule: imported.name)
                else { continue }

                let verdict = context.permits(
                    from: role,
                    to: importedRole,
                    fromPackage: file.module?.packageDirectory,
                    toPackage: imported.packageDirectory
                )

                switch verdict {
                case .permitted:
                    continue

                case .roleRefused:
                    violations.append(
                        Violation(
                            rule: identifier,
                            severity: defaultSeverity,
                            file: file.path,
                            line: reference.line,
                            summary: "`\(role)` imports `\(imported.name)`, which belongs to `\(importedRole)`",
                            fix: BoundaryPhrasing.invert(
                                role: role,
                                definition: definition,
                                towards: importedRole,
                                file: file.path,
                                advisor: advisor
                            ),
                            source: Sources.dependencyRule
                        )
                    )

                case .notVisible:
                    violations.append(
                        Violation(
                            rule: "not-visible",
                            severity: defaultSeverity,
                            file: file.path,
                            line: reference.line,
                            summary: "`\(imported.name)` is `\(importedRole)`, which `\(role)` may not see",
                            fix: context.definition(for: importedRole)?.reason
                                ?? BoundaryPhrasing.refusedVisibility(to: importedRole, from: role, context: context),
                            source: Sources.testSupport
                        )
                    )

                case .sameRoleRefused:
                    violations.append(
                        Violation(
                            rule: "feature-isolation",
                            severity: defaultSeverity,
                            file: file.path,
                            line: reference.line,
                            summary: "`\(imported.name)` is another `\(role)` module, and this layer keeps its siblings apart",
                            fix: definition.reason ?? (
                                "Two `\(role)` modules that know about each other cannot be built, tested or "
                                + "deleted separately, which is the only reason they were split up. Move the shared "
                                + "part down into a layer they both already depend on, or let them meet at the "
                                + "composition root, which is the one place allowed to know about both."
                            ),
                            source: Sources.componentCohesion
                        )
                    )
                }
            }
        }

        return violations
    }
}
