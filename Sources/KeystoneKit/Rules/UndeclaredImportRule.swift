import Foundation

/// Every `import` of a first-party module should be a dependency the manifest
/// admits to.
///
/// SwiftPM will happily compile a target that imports a module it reaches only
/// because something else pulled it in. It works until the day the module in
/// between drops its own dependency, and then a package that changed nothing
/// stops building. A warning rather than a refusal, because the code is
/// correct today and the fix is a one-line manifest edit.
public struct UndeclaredImportRule: Rule {
    public let identifier = "imports-are-declared"
    public let defaultSeverity: Severity = .warning
    public var needsWholeProject: Bool { true }

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        var violations: [Violation] = []

        for file in context.files {
            guard let module = file.module,
                  // Only SwiftPM states dependencies precisely enough to hold
                  // to this. An Xcode target's implicit dependencies are not
                  // written down anywhere this tool can read.
                  Paths.lastComponent(of: module.manifestPath) == "Package.swift" else { continue }

            let declared = context.graph.edges[module.name] ?? []

            for reference in file.facts.imports {
                guard reference.module != module.name,
                      context.graph.modules[reference.module] != nil,
                      !declared.contains(reference.module) else { continue }

                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: file.path,
                        line: reference.line,
                        summary: "`\(module.name)` imports `\(reference.module)` without declaring it",
                        fix: "Add `\(reference.module)` to this target's `dependencies` in \(module.manifestPath). "
                            + "It compiles today only because another dependency happens to expose it, so the "
                            + "build breaks the moment that one changes — and the manifest currently understates "
                            + "what this module actually needs.",
                        source: Sources.dependencyRule
                    )
                )
            }
        }

        return violations
    }
}
