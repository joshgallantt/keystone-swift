import Foundation

/// A dependency the manifest declares that no file in the target imports.
///
/// The inverse of `imports-are-declared`, and a different fault with a
/// different correction: that rule says the manifest understates what the
/// module needs, this one says it overstates it. Both are worth having, and
/// two other tools in this ecosystem treat the pair as table stakes —
/// GetYourGuide's `spmgraph` and `tuist inspect dependencies`, which reports
/// exactly `implicit` and `redundant`. This tool had only the first half.
///
/// The cost of a dependency nobody imports is not a slow build. It is that the
/// manifest stops describing the architecture. A module that declares six
/// dependencies and uses two looks coupled to six, so nobody dares delete
/// anything, and the graph the whole tool reasons from is four edges wrong.
/// Removing the line is also the safest edit in the repository: if the module
/// really did need it, the build says so immediately.
///
/// A warning. The code compiles and runs; the manifest is merely inaccurate.
///
/// Three exemptions, each for a case where an unused edge is real:
///
/// - Only SwiftPM. An Xcode target's dependencies are implicit and this tool
///   cannot read them precisely enough to accuse anyone.
/// - Only first-party modules, taken from the resolved graph. An external
///   product's name and its module name are frequently different, and guessing
///   would produce a confident accusation about somebody else's package.
/// - Never a dependency that holds no Swift. An Objective-C target is imported
///   from `.m` files this tool does not read, so silence there is ignorance
///   rather than evidence.
public struct UnusedDependencyRule: Rule {
    public let identifier = "dependencies-are-used"
    public let defaultSeverity: Severity = .warning
    public var needsWholeProject: Bool { true }

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        // The single-file path parses one file, so every import in every other
        // file of the module is invisible, and an unread import cannot be told
        // apart from an absent one. The rule would accuse a module of not using
        // a dependency that the file next to it imports. `--changed` is safe:
        // it parses the whole project and filters the violations afterwards.
        guard case .project = context.scope else { return [] }

        var importsByModule: [String: Set<String>] = [:]
        for file in context.files {
            guard let module = file.module else { continue }
            importsByModule[module.name, default: []]
                .formUnion(file.facts.imports.map(\.module))
        }

        var swiftBearing: Set<String> = []
        for file in context.files {
            if let module = file.module { swiftBearing.insert(module.name) }
        }

        var violations: [Violation] = []

        for module in context.graph.orderedModules {
            guard Paths.lastComponent(of: module.manifestPath) == "Package.swift" else { continue }

            let imported = importsByModule[module.name] ?? []

            // The unit is the entry the manifest actually contains, not the
            // edge the graph derived from it. A product may vend several
            // targets, and `resolve` returns all of them, so reading the edges
            // directly accused the reference project fifty-one times: a module
            // depending on one product that vends four targets, and importing
            // one of them, looked like three unused dependencies. There is no
            // line in the manifest to delete for any of the three. A declared
            // entry is redundant only when NOTHING it brings in is imported.
            for entry in module.declaredDependencies.sorted() {
                let brings = context.graph.resolve(dependencyName: entry)
                    .filter { $0 != module.name }
                guard !brings.isEmpty,
                      brings.allSatisfy({ swiftBearing.contains($0) }),
                      brings.allSatisfy({ !imported.contains($0) }) else { continue }

                let vends = brings.count == 1 && brings[0] == entry
                    ? ""
                    : " — which brings in " + brings.sorted().map { "`\($0)`" }.joined(separator: ", ")

                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: module.manifestPath,
                        line: module.manifestLine,
                        summary: "`\(module.name)` declares `\(entry)`\(vends) and imports none of it",
                        fix: "Remove `\(entry)` from this target's `dependencies` in "
                            + "\(module.manifestPath). Until then the manifest claims a coupling that does "
                            + "not exist, which makes the module look harder to move than it is and leaves "
                            + "the dependency graph — the thing every boundary rule reads — wrong by an "
                            + "edge. If the module does turn out to need it, the build says so on the next "
                            + "compile, which makes this the cheapest change in the repository to try.",
                        source: Sources.dependencyRule
                    )
                )
            }
        }

        return violations
    }
}
