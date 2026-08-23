import Foundation

public enum ModuleKind: String, Sendable, Codable {
    case library
    case executable
    case test
    case app
    case system
    case binary
    case plugin

    public var isTest: Bool { self == .test }
}

/// One compilation unit: an SPM target or an Xcode native target.
///
/// The module is the unit the compiler can actually enforce a boundary at, so
/// it is the unit this tool reasons about. A rule proved at the module level
/// cannot be worked around by an import, because the linker never sees one.
public struct Module: Sendable {
    public var name: String
    public var kind: ModuleKind
    public var packageName: String?
    /// Repository-relative directory of the package or project declaring it.
    public var packageDirectory: String?
    /// Repository-relative directories whose Swift files belong to this module.
    public var sourceRoots: [String]
    public var excludedPaths: [String]
    /// Dependency names exactly as written in the manifest, before resolution.
    public var declaredDependencies: [String]
    /// Files named one by one rather than claimed by a directory. Xcode's
    /// classic target membership is a list, not a tree, and flattening it into
    /// a directory would hand a target files it does not compile.
    public var explicitFiles: Set<String>
    public var manifestPath: String
    public var manifestLine: Int?

    public init(
        name: String,
        kind: ModuleKind,
        packageName: String? = nil,
        packageDirectory: String? = nil,
        sourceRoots: [String] = [],
        excludedPaths: [String] = [],
        declaredDependencies: [String] = [],
        explicitFiles: Set<String> = [],
        manifestPath: String,
        manifestLine: Int? = nil
    ) {
        self.name = name
        self.kind = kind
        self.packageName = packageName
        self.packageDirectory = packageDirectory
        self.sourceRoots = sourceRoots
        self.excludedPaths = excludedPaths
        self.declaredDependencies = declaredDependencies
        self.explicitFiles = explicitFiles
        self.manifestPath = manifestPath
        self.manifestLine = manifestLine
    }

    /// Whether this module claims the given repository-relative file.
    /// Longest root wins at the graph level; this only answers containment.
    public func claims(_ path: String) -> Bool {
        if explicitFiles.contains(path) { return true }
        guard sourceRoots.contains(where: { path.hasPrefix($0 + "/") || path == $0 }) else { return false }
        return !excludedPaths.contains { path.hasPrefix($0 + "/") || path == $0 }
    }

    /// The length of the claim, so a nested target beats its parent when both
    /// could plausibly own a file.
    public func claimSpecificity(_ path: String) -> Int {
        // Naming a file outright is the strongest claim there is, so it beats
        // any directory that happens to contain it.
        if explicitFiles.contains(path) { return path.count + 1_000_000 }
        return sourceRoots
            .filter { path.hasPrefix($0 + "/") || path == $0 }
            .map(\.count)
            .max() ?? 0
    }
}

public struct ProductInfo: Sendable {
    public var name: String
    public var targets: [String]
    public var packageName: String

    public init(name: String, targets: [String], packageName: String) {
        self.name = name
        self.targets = targets
        self.packageName = packageName
    }
}

/// Every module in the repository and every edge between them.
///
/// Edges are split by origin. A first-party edge is a boundary the project
/// controls and can therefore be held to a rule; an external edge is a fact
/// about someone else's code, and the only question worth asking of it is
/// which of our layers is allowed to touch it.
public struct ProjectGraph: Sendable {
    public var modules: [String: Module]
    public var products: [String: ProductInfo]
    public var externalPackages: Set<String>
    /// Module name to the first-party modules it depends on.
    public var edges: [String: Set<String>]
    /// Module name to the external product names it depends on.
    public var externalEdges: [String: Set<String>]

    public init(
        modules: [String: Module] = [:],
        products: [String: ProductInfo] = [:],
        externalPackages: Set<String> = [],
        edges: [String: Set<String>] = [:],
        externalEdges: [String: Set<String>] = [:]
    ) {
        self.modules = modules
        self.products = products
        self.externalPackages = externalPackages
        self.edges = edges
        self.externalEdges = externalEdges
    }

    public var orderedModules: [Module] {
        modules.values.sorted { $0.name < $1.name }
    }

    /// The module owning a file, chosen by the most specific source root so
    /// that a target nested inside another target's directory wins.
    public func module(owning path: String) -> Module? {
        var best: Module?
        var bestSpecificity = 0
        for module in orderedModules where module.claims(path) {
            let specificity = module.claimSpecificity(path)
            if specificity > bestSpecificity {
                best = module
                bestSpecificity = specificity
            }
        }
        return best
    }

    /// Whether the name refers to anything the repository itself builds.
    public func isFirstParty(_ name: String) -> Bool {
        modules[name] != nil || products[name] != nil
    }

    /// Modules reached by a name as written in a manifest: a target directly,
    /// or every target behind a product.
    public func resolve(dependencyName name: String) -> [String] {
        if modules[name] != nil { return [name] }
        if let product = products[name] { return product.targets }
        return []
    }
}
