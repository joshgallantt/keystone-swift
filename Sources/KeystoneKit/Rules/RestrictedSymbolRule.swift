import Foundation

/// Closes the loophole an allowed umbrella framework leaves open.
///
/// `Foundation` is permitted almost everywhere, and `URLSession`, `FileManager`
/// and `UserDefaults` all arrive inside it. An import rule cannot see the
/// difference; a rule that reads the names a file actually mentions can. This
/// is why a layer may name symbols it refuses as well as frameworks.
public struct RestrictedSymbolRule: Rule {
    public let identifier = "restricted-symbols"
    public let defaultSeverity: Severity = .error

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        var violations: [Violation] = []

        for file in context.files {
            guard let role = file.role, let definition = context.definition(for: role),
                  !definition.deniedSymbols.isEmpty else { continue }

            let denied = Set(definition.deniedSymbols)

            for reference in file.facts.typeReferences where denied.contains(reference.name) {
                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: file.path,
                        line: reference.line,
                        summary: "`\(role)` uses `\(reference.name)`, which this layer refuses",
                        fix: definition.reason ?? (
                            "`\(reference.name)` arrives through a framework this layer is otherwise allowed, "
                            + "which is how infrastructure gets into a layer that was supposed to be free of it. "
                            + "Declare the capability you need as a protocol here and implement it where "
                            + "`\(reference.name)` belongs."
                        ),
                        source: Sources.dependencyRule
                    )
                )
            }
        }

        return violations
    }
}
