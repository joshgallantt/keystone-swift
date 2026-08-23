import Foundation

/// A global instance is a dependency nobody declared.
///
/// `Repository.shared` is reached for rather than passed in, so the layer using
/// it has a dependency that appears in no initialiser, no manifest and no test
/// setup — and cannot be substituted. It applies only to layers that are not
/// composition roots: wiring code exists precisely to hold concrete instances,
/// and forbidding it there would be forbidding it from doing its job.
public struct SharedSingletonRule: Rule {
    public let identifier = "no-shared-singletons"
    public let defaultSeverity: Severity = .warning

    static let names: Set<String> = ["shared", "sharedInstance", "instance"]

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        var violations: [Violation] = []

        for file in context.files {
            guard let role = file.role, role != .tests,
                  let definition = context.definition(for: role),
                  !definition.dependsOnAnything else { continue }

            for declaration in file.facts.declarations
            where declaration.isStatic && SharedSingletonRule.names.contains(declaration.name) {
                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: file.path,
                        line: declaration.line,
                        summary: "`\(role)` declares a shared instance, which callers reach for instead of receiving",
                        fix: "Take the dependency through the initialiser instead and let the composition root "
                            + "decide how many of these exist. As a static, it is a dependency that appears in no "
                            + "initialiser and no test setup, so every type that touches it silently requires it — "
                            + "and none of them can be tested without the real one.",
                        source: Sources.compositionRoot
                    )
                )
            }
        }

        return violations
    }
}
