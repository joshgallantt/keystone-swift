import Foundation

public struct ModuleFinding: Sendable {
    public var name: String
    public var role: Role?
    public var evidence: String
    public var fileCount: Int
}

public struct InferenceReport: Sendable {
    public var configuration: Configuration
    public var modules: [ModuleFinding]
    public var directories: [(role: Role, patterns: [String])]
    public var fileCounts: [Role: Int]
    public var unclassifiedFiles: [String]
}

/// Reads a repository and proposes a configuration for it.
///
/// This runs once, and its output is a file a person reviews. That is the whole
/// design: inference is allowed to be heuristic precisely because it never runs
/// during a check. Everything the checker does afterwards is a pure function of
/// the reviewed file, so the guesses made here are visible, arguable and
/// editable rather than buried in the tool's behaviour.
public struct RoleInference: Sendable {
    private let fileSystem: FileSystemProbing
    private let analyzer = SwiftSourceAnalyzer()

    public init(fileSystem: FileSystemProbing = RealFileSystem()) {
        self.fileSystem = fileSystem
    }

    public func infer(root: String, exclude: [String] = Configuration.defaultExclusions) -> InferenceReport {
        let root = Paths.canonical(root)
        let base = Configuration(exclude: exclude)
        let scanned = ProjectScanner(fileSystem: fileSystem).scan(root: root, configuration: base)
        let catalog = base.catalog

        var importsByModule: [String: Set<String>] = [:]
        var externalByModule: [String: Bool] = [:]
        var filesByModule: [String: [String]] = [:]

        for path in scanned.swiftFiles {
            guard let module = scanned.graph.module(owning: path) else { continue }
            filesByModule[module.name, default: []].append(path)

            guard let content = fileSystem.contents(of: Paths.absolute(path, in: root)) else { continue }
            let facts = analyzer.analyze(path: path, content: content)
            let external = scanned.graph.externalEdges[module.name] ?? []
            for reference in facts.imports {
                if let category = catalog.category(of: reference.module) {
                    importsByModule[module.name, default: []].insert(category)
                }
                if external.contains(reference.module) {
                    externalByModule[module.name] = true
                }
            }
        }

        var moduleRoles: [String: Role] = [:]
        var evidence: [String: String] = [:]

        for module in scanned.graph.orderedModules {
            if let (role, why) = firstPass(
                module: module,
                categories: importsByModule[module.name] ?? [],
                hasExternal: externalByModule[module.name] ?? false
            ) {
                moduleRoles[module.name] = role
                evidence[module.name] = why
            }
        }

        for module in scanned.graph.orderedModules where moduleRoles[module.name] == nil {
            let (role, why) = secondPass(module: module, graph: scanned.graph, known: moduleRoles)
            if let role { moduleRoles[module.name] = role }
            evidence[module.name] = why
        }

        // Files, which is what the configuration actually addresses.
        var directoriesByRole: [Role: Set<String>] = [:]
        var fileCounts: [Role: Int] = [:]
        var unclassified: [String] = []

        for path in scanned.swiftFiles {
            let directory = Paths.directory(of: path)
            let module = scanned.graph.module(owning: path)

            var role: Role?
            if module?.kind.isTest == true {
                role = .tests
            } else if let fromPath = LayerVocabulary.role(forDirectory: directory) {
                role = fromPath
            } else if let moduleName = module?.name {
                role = moduleRoles[moduleName]
            }

            guard let role else {
                unclassified.append(path)
                continue
            }
            directoriesByRole[role, default: []].insert(directory)
            fileCounts[role, default: 0] += 1
        }

        let packageDirectories = Set(scanned.graph.orderedModules.compactMap(\.packageDirectory))

        var patterns: [Role: [String]] = [:]
        for role in Role.conventionalOrder {
            let own = Array(directoriesByRole[role] ?? [])
            guard !own.isEmpty else { continue }
            let others = directoriesByRole
                .filter { $0.key != role }
                .flatMap { Array($0.value) }
            patterns[role] = PathGeneralizer.generalize(own, avoiding: others, packages: packageDirectories)
        }

        var configuration = Presets.cleanArchitecture(paths: patterns)
        configuration.name = Paths.lastComponent(of: root)
        configuration.exclude = exclude

        let findings = scanned.graph.orderedModules.map { module in
            ModuleFinding(
                name: module.name,
                role: moduleRoles[module.name],
                evidence: evidence[module.name] ?? "no evidence",
                fileCount: filesByModule[module.name]?.count ?? 0
            )
        }

        return InferenceReport(
            configuration: configuration,
            modules: findings,
            directories: Role.conventionalOrder.compactMap { role in
                patterns[role].map { (role, $0) }
            },
            fileCounts: fileCounts,
            unclassifiedFiles: unclassified.sorted()
        )
    }

    /// Evidence a module carries on its own: what the build system calls it,
    /// what its directories are named, what it imports.
    private func firstPass(
        module: Module,
        categories: Set<String>,
        hasExternal: Bool
    ) -> (Role, String)? {
        if module.kind.isTest { return (.tests, "test target") }
        if module.kind == .app { return (.composition, "application target") }

        for root in module.sourceRoots {
            if let match = LayerVocabulary.match(forDirectory: root) {
                return (match.role, "directory named `\(match.segment)`")
            }
        }
        if let directory = module.packageDirectory,
           let match = LayerVocabulary.match(forDirectory: directory) {
            return (match.role, "package under `\(match.segment)`")
        }

        if categories.contains(FrameworkCatalog.ui) {
            return (.presentation, "imports a user-interface framework")
        }
        if categories.contains(FrameworkCatalog.persistence)
            || categories.contains(FrameworkCatalog.networking)
            || categories.contains(FrameworkCatalog.crypto) {
            return (.data, "imports a storage, network or crypto framework")
        }
        if hasExternal {
            return (.data, "depends on a third-party package")
        }

        return nil
    }

    /// Evidence a module carries only in relation to others. A module that
    /// depends on both a domain and a data module is wiring them together,
    /// whatever it is called.
    private func secondPass(
        module: Module,
        graph: ProjectGraph,
        known: [String: Role]
    ) -> (Role?, String) {
        let dependencyRoles = Set((graph.edges[module.name] ?? []).compactMap { known[$0] })

        if dependencyRoles.contains(.domain) && dependencyRoles.contains(.data) {
            return (.composition, "depends on both a domain and a data module")
        }
        if dependencyRoles.contains(.presentation) {
            return (.composition, "depends on a presentation module")
        }
        if dependencyRoles.contains(.domain) {
            return (.data, "depends on a domain module without being a screen")
        }
        if (graph.edges[module.name] ?? []).isEmpty {
            return (.domain, "depends on nothing, so it is a candidate for the stable centre")
        }
        return (.domain, "no clear evidence — review this one")
    }
}
