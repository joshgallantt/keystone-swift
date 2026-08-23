import Foundation

/// Keeps platform frameworks out of the layers that must not know about them.
///
/// A layer states the *categories* it refuses — `ui`, `persistence`, `crypto` —
/// rather than a list of framework names, so a project gets the rule it meant
/// even for frameworks that did not exist when the rule was written. This is
/// the check that stops business rules quietly becoming SwiftUI code.
public struct FrameworkBoundaryRule: Rule {
    public let identifier = "framework-purity"
    public let defaultSeverity: Severity = .error

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        var violations: [Violation] = []

        for file in context.files {
            guard let role = file.role, let definition = context.definition(for: role),
                  !definition.deniedFrameworks.isEmpty else { continue }

            for reference in file.facts.imports {
                guard let category = context.catalog.category(of: reference.module),
                      definition.deniedFrameworks.contains(category) else { continue }

                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: file.path,
                        line: reference.line,
                        summary: "`\(role)` imports `\(reference.module)`, a `\(category)` framework it refuses",
                        fix: definition.reason ?? FrameworkBoundaryRule.advice(
                            role: role,
                            category: category,
                            framework: reference.module,
                            context: context
                        ),
                        source: Sources.businessRules
                    )
                )
            }
        }

        return violations
    }

    /// Names the layers that *are* allowed the framework, so the reader is told
    /// where the code goes rather than only that it cannot stay.
    static func advice(role: Role, category: String, framework: String, context: RuleContext) -> String {
        let permitted = context.configuration.orderedRoles
            .filter { !$0.definition.deniedFrameworks.contains(category) && $0.name != role }
            .map { "`\($0.name)`" }

        var text = "A layer that imports `\(framework)` is tied to it: it cannot be tested without it, "
            + "and it changes when the framework changes. Declare what you need from `\(framework)` as a "
            + "protocol here, and put the implementation where the framework is allowed"

        if permitted.isEmpty {
            text += "."
        } else {
            text += " — \(permitted.joined(separator: ", "))."
        }

        return text
    }
}
