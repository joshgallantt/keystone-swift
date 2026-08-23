import Foundation

/// Keeps other people's packages out of the layers that must outlive them.
///
/// Only imports the manifest has already confirmed to be external are judged.
/// An import this tool cannot place is left alone: silence about something
/// unrecognised is the correct answer, and a false accusation is what teaches
/// a team to switch the tool off.
public struct ThirdPartyBoundaryRule: Rule {
    public let identifier = "third-party-boundary"
    public let defaultSeverity: Severity = .error

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        var violations: [Violation] = []

        for file in context.files {
            guard let role = file.role, let definition = context.definition(for: role),
                  !definition.allowsThirdParty, let module = file.module else { continue }

            let external = context.graph.externalEdges[module.name] ?? []

            for reference in file.facts.imports where external.contains(reference.module) {
                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: file.path,
                        line: reference.line,
                        summary: "`\(role)` imports `\(reference.module)`, a third-party package",
                        fix: definition.reason ?? (
                            "`\(role)` is the part of this codebase meant to outlive its dependencies. A package "
                            + "here means a stable layer now changes on somebody else's release schedule. Declare "
                            + "the capability as a protocol in `\(role)` and put the adapter that uses "
                            + "`\(reference.module)` in a layer that may take the dependency."
                        ),
                        source: Sources.dependencyRule
                    )
                )
            }
        }

        return violations
    }
}
