import Foundation

/// The dependency rule as the build system sees it.
///
/// An import can be removed in a moment; a manifest edge is what actually lets
/// one module see another. Checking both matters because they fail differently:
/// a stray import is a mistake, while a manifest edge that should not exist is
/// a decision — and it is the decision that quietly makes the next hundred
/// stray imports legal.
public struct TargetDependencyRule: Rule {
    public let identifier = "target-dependency-rule"
    public var emittedIdentifiers: [String] { [identifier, "feature-isolation", "third-party-boundary"] }
    public let defaultSeverity: Severity = .error
    public var needsWholeProject: Bool { true }

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        let advisor = DestinationAdvisor(configuration: context.configuration)
        var violations: [Violation] = []

        for module in context.graph.orderedModules {
            guard let role = context.assignment.role(ofModule: module.name),
                  let definition = context.configuration.definition(for: role) else { continue }

            for dependencyName in (context.graph.edges[module.name] ?? []).sorted() {
                guard let dependency = context.graph.modules[dependencyName],
                      let dependencyRole = context.assignment.role(ofModule: dependencyName) else { continue }

                let verdict = context.permits(
                    from: role,
                    to: dependencyRole,
                    fromPackage: module.packageDirectory,
                    toPackage: dependency.packageDirectory
                )

                switch verdict {
                case .permitted:
                    continue

                case .roleRefused:
                    violations.append(
                        Violation(
                            rule: identifier,
                            severity: defaultSeverity,
                            file: module.manifestPath,
                            line: module.manifestLine,
                            summary: "`\(module.name)` (`\(role)`) declares a dependency on `\(dependencyName)` (`\(dependencyRole)`)",
                            fix: TargetDependencyRule.manifestAdvice(
                                module: module,
                                role: role,
                                dependency: dependencyName,
                                dependencyRole: dependencyRole,
                                definition: definition,
                                advisor: advisor
                            ),
                            source: Sources.dependencyRule
                        )
                    )

                case .sameRoleRefused:
                    violations.append(
                        Violation(
                            rule: "feature-isolation",
                            severity: defaultSeverity,
                            file: module.manifestPath,
                            line: module.manifestLine,
                            summary: "`\(module.name)` declares a dependency on `\(dependencyName)`, a sibling `\(role)` module",
                            fix: definition.reason ?? (
                                "Remove the dependency from the manifest. Sibling `\(role)` modules meet at the "
                                + "composition root, which is the one component allowed to know that both exist. "
                                + "If they genuinely share code, that shared part belongs in a layer beneath them both."
                            ),
                            source: Sources.componentCohesion
                        )
                    )
                }
            }

            guard !definition.allowsThirdParty else { continue }

            for external in (context.graph.externalEdges[module.name] ?? []).sorted() {
                violations.append(
                    Violation(
                        rule: "third-party-boundary",
                        severity: defaultSeverity,
                        file: module.manifestPath,
                        line: module.manifestLine,
                        summary: "`\(module.name)` (`\(role)`) declares a dependency on the third-party product `\(external)`",
                        fix: definition.reason ?? (
                            "A `\(role)` module that links `\(external)` is no longer stable — it now changes when "
                            + "someone else releases. Take the dependency out of this target, declare what you need "
                            + "as a protocol here, and let a layer that may take the package implement it."
                        ),
                        source: Sources.dependencyRule
                    )
                )
            }
        }

        return violations
    }

    static func manifestAdvice(
        module: Module,
        role: Role,
        dependency: String,
        dependencyRole: Role,
        definition: RoleDefinition,
        advisor: DestinationAdvisor
    ) -> String {
        if let reason = definition.reason { return reason }
        return "Remove `\(dependency)` from this target's dependencies. `\(role)` may depend on "
            + "\(BoundaryPhrasing.permittedTargets(definition)). The manifest is where this boundary becomes "
            + "real: while the edge is declared, the compiler will keep letting `\(module.name)` reach into "
            + "`\(dependencyRole)`, whatever the imports say. Invert it — declare a protocol in `\(role)` and "
            + "have `\(dependency)` conform, wired together by the composition root."
    }
}
