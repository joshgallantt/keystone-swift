import Foundation

public struct ScannedProject: Sendable {
    public var root: String
    public var graph: ProjectGraph
    /// Repository-relative Swift files, sorted, exclusions already applied.
    public var swiftFiles: [String]
    /// Every file the walk saw, Swift or not. Structural comparison between
    /// peer modules needs to notice a missing fixture, licence or resource
    /// just as much as a missing type.
    public var allFiles: [String]
    public var packageManifests: [String]
    public var xcodeProjects: [String]
}

/// Walks a repository once and reports what is there.
///
/// Discovery is separated from judgement on purpose. Everything downstream is a
/// pure function of `ScannedProject` and a `Configuration`, which is what makes
/// the rules testable without a directory on disk and what makes two runs on
/// the same commit produce the same report.
public struct ProjectScanner: Sendable {
    private let fileSystem: FileSystemProbing

    public init(fileSystem: FileSystemProbing = RealFileSystem()) {
        self.fileSystem = fileSystem
    }

    /// Directories never worth descending into. Pruning at the directory level
    /// rather than filtering files afterwards is the difference between a
    /// hook that answers instantly and one an agent learns to resent.
    private static let prunedDirectories: Set<String> = [
        ".git", ".build", ".swiftpm", "DerivedData", "Pods", "Carthage",
        "node_modules", ".index-build", "build", ".venv"
    ]

    public func scan(root: String, configuration: Configuration) -> ScannedProject {
        let exclusions = GlobSet(configuration.exclude)
        var allFiles: [String] = []
        var swiftFiles: [String] = []
        var packageManifests: [String] = []
        var xcodeProjects: [String] = []

        walk(root: root, exclusions: exclusions) { relative, isDirectory in
            if isDirectory {
                if relative.hasSuffix(".xcodeproj") { xcodeProjects.append(relative) }
                return
            }
            allFiles.append(relative)
            if relative.hasSuffix(".swift") {
                if Paths.lastComponent(of: relative) == "Package.swift" {
                    packageManifests.append(relative)
                } else {
                    swiftFiles.append(relative)
                }
            }
        }

        allFiles.sort()
        swiftFiles.sort()
        packageManifests.sort()
        xcodeProjects.sort()

        let graph = buildGraph(
            root: root,
            packageManifests: packageManifests,
            xcodeProjects: xcodeProjects
        )

        return ScannedProject(
            root: root,
            graph: graph,
            swiftFiles: swiftFiles,
            allFiles: allFiles,
            packageManifests: packageManifests,
            xcodeProjects: xcodeProjects
        )
    }

    private func walk(
        root: String,
        exclusions: GlobSet,
        visit: (_ relative: String, _ isDirectory: Bool) -> Void
    ) {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let relative = Paths.relative(url.path, to: root)
            let name = Paths.lastComponent(of: relative)

            if isDirectory {
                if ProjectScanner.prunedDirectories.contains(name) {
                    enumerator.skipDescendants()
                    continue
                }
                if name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") {
                    visit(relative, true)
                    enumerator.skipDescendants()
                    continue
                }
                // A directory pattern is tested by asking whether it could
                // contain an excluded file, which is what `**` in an exclusion
                // is always saying.
                if exclusions.matches(relative + "/_") {
                    enumerator.skipDescendants()
                    continue
                }
                continue
            }

            if exclusions.matches(relative) { continue }
            visit(relative, false)
        }
    }

    private func buildGraph(root: String, packageManifests: [String], xcodeProjects: [String]) -> ProjectGraph {
        var modules: [String: Module] = [:]
        var products: [String: ProductInfo] = [:]
        var externalPackages: Set<String> = []

        let packageParser = PackageManifestParser(fileSystem: fileSystem)
        for manifest in packageManifests {
            guard let source = fileSystem.contents(of: Paths.absolute(manifest, in: root)),
                  let parsed = packageParser.parse(source: source, manifestPath: manifest, root: root)
            else { continue }
            for target in parsed.targets where modules[target.name] == nil {
                modules[target.name] = target
            }
            for product in parsed.products where products[product.name] == nil {
                products[product.name] = product
            }
            externalPackages.formUnion(parsed.externalPackages)
        }

        let projectParser = XcodeProjectParser()
        for project in xcodeProjects {
            let pbxproj = Paths.join(project, "project.pbxproj")
            guard let source = fileSystem.contents(of: Paths.absolute(pbxproj, in: root)),
                  let parsed = projectParser.parse(source: source, projectPath: project)
            else { continue }
            for target in parsed.targets where modules[target.name] == nil {
                modules[target.name] = target
            }
            externalPackages.formUnion(parsed.externalPackages)
        }

        var edges: [String: Set<String>] = [:]
        var externalEdges: [String: Set<String>] = [:]
        var graph = ProjectGraph(
            modules: modules,
            products: products,
            externalPackages: externalPackages
        )

        for module in graph.orderedModules {
            var firstParty: Set<String> = []
            var external: Set<String> = []
            for dependency in module.declaredDependencies {
                let resolved = graph.resolve(dependencyName: dependency)
                if resolved.isEmpty {
                    external.insert(dependency)
                } else {
                    firstParty.formUnion(resolved.filter { $0 != module.name })
                }
            }
            edges[module.name] = firstParty
            externalEdges[module.name] = external
        }

        graph.edges = edges
        graph.externalEdges = externalEdges
        return graph
    }
}
