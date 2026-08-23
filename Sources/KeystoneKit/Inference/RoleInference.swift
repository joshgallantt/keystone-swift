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

    /// Reads a repository and reports what the checker will make of it.
    ///
    /// This runs the same assignment `check` runs, rather than a second,
    /// friendlier one. An `init` that explained the project differently from
    /// the way it is actually judged would be worse than no `init` at all.
    public func infer(
        root: String,
        exclude: [String] = Configuration.defaultExclusions,
        pinLayout: Bool = false
    ) -> InferenceReport {
        let root = Paths.canonical(root)
        let base = Presets.cleanArchitecture(paths: [:])
        var configuration = base
        configuration.exclude = exclude

        let scanned = ProjectScanner(fileSystem: fileSystem).scan(root: root, configuration: configuration)
        let assignment = RoleAssignment(
            configuration: configuration,
            graph: scanned.graph,
            swiftFiles: scanned.swiftFiles
        )

        var directoriesByRole: [Role: Set<String>] = [:]
        var fileCounts: [Role: Int] = [:]
        for (file, role) in assignment.fileRoles {
            directoriesByRole[role, default: []].insert(Paths.directory(of: file))
            fileCounts[role, default: 0] += 1
        }

        // Paths are written only when asked for. Freezing this repository's
        // directories into a manifest is what made the file project-specific,
        // and the derivation runs every time anyway.
        var patterns: [Role: [String]] = [:]
        if pinLayout {
            let packages = Set(scanned.graph.orderedModules.compactMap(\.packageDirectory))
            for role in Role.conventionalOrder {
                let own = Array(directoriesByRole[role] ?? [])
                guard !own.isEmpty else { continue }
                let others = directoriesByRole.filter { $0.key != role }.flatMap { Array($0.value) }
                patterns[role] = PathGeneralizer.generalize(own, avoiding: others, packages: packages)
            }
        }

        var result = Presets.cleanArchitecture(paths: patterns)
        result.name = Paths.lastComponent(of: root)
        result.exclude = exclude

        var filesByModule: [String: Int] = [:]
        for file in scanned.swiftFiles {
            guard let module = scanned.graph.module(owning: file) else { continue }
            filesByModule[module.name, default: 0] += 1
        }

        return InferenceReport(
            configuration: result,
            modules: scanned.graph.orderedModules.map { module in
                ModuleFinding(
                    name: module.name,
                    role: assignment.role(ofModule: module.name),
                    evidence: assignment.evidence[module.name] ?? "nothing placed it",
                    fileCount: filesByModule[module.name] ?? 0
                )
            },
            directories: Role.conventionalOrder.compactMap { role in
                patterns[role].map { (role, $0) }
            },
            fileCounts: fileCounts,
            unclassifiedFiles: assignment.unclassifiedFiles
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
