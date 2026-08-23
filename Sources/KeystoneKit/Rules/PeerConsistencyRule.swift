import Foundation

/// Sibling modules should be shaped alike, and the odd one out is worth saying.
///
/// Most conventions in a codebase were never written down. Nine components have
/// a fixtures file in their unit tests and the tenth does not — nobody decided
/// that, it just never got added, and no rule authored in advance could have
/// caught it because nobody knew the convention existed until it was broken.
///
/// So this rule does not check against a specification. It compares peers with
/// each other, and reports what the majority does and the minority does not.
/// A warning, always: a difference is evidence of a decision nobody made, not
/// proof of a mistake, and sometimes the odd one out is right.
///
/// Peers are packages *made of the same layers*, which took a wrong turn first.
/// Grouping by directory instead — everything under `Component/` — treated a
/// package of pure value objects as a peer of a full component with storage and
/// a container, and then reported it for lacking both. Those were not
/// discrepancies to be exempted one by one; they were the rule comparing things
/// that were never alike. A package with no data layer is not a component
/// missing its data layer, and the layers a package is built from say so
/// without anybody having to write it down.
public struct PeerConsistencyRule: Rule {
    public let identifier = "peer-consistency"
    public let defaultSeverity: Severity = .warning
    public var needsWholeProject: Bool { true }

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        let settings = context.configuration.consistency
        let ignored = GlobSet(settings.ignore)
        let exempt = ExemptionSet(settings.exempt)

        var layersByPackage: [String: Set<String>] = [:]
        for module in context.graph.orderedModules {
            guard let package = module.packageDirectory, !package.isEmpty,
                  let role = context.assignment.role(ofModule: module.name) else { continue }
            layersByPackage[package, default: []].insert(role.rawValue)
        }

        var groups: [String: [String]] = [:]
        for (package, layers) in layersByPackage {
            groups[layers.sorted().joined(separator: "+"), default: []].append(package)
        }

        var violations: [Violation] = []

        for shape in groups.keys.sorted() {
            let peers = groups[shape]!.sorted()
            guard peers.count >= settings.minimumPeers else { continue }

            var holders: [String: [String]] = [:]
            for package in peers {
                for feature in PeerConsistencyRule.features(of: package, in: context.allFiles, ignoring: ignored) {
                    holders[feature, default: []].append(package)
                }
            }

            var missing: [String: Set<String>] = [:]
            for feature in holders.keys.sorted() {
                let having = holders[feature]!
                guard having.count < peers.count else { continue }
                let share = Double(having.count) / Double(peers.count)
                guard share >= settings.threshold else { continue }

                for package in peers where !having.contains(package) {
                    missing[package, default: []].insert(feature)
                }
            }

            for package in peers.sorted() {
                guard let absent = missing[package] else { continue }

                // A package missing a whole directory is also missing
                // everything in it. Reporting the contents as well turns one
                // fact into fifteen and buries it.
                // Still a peer — its shape is evidence about the others — but
                // absences already accounted for are not reported again.
                for feature in PeerConsistencyRule.outermost(absent).sorted()
                where !exempt.covers(package: package, feature: feature) {
                    violations.append(
                        violation(
                            package: package,
                            shape: shape,
                            feature: feature,
                            having: holders[feature]!.count,
                            total: peers.count,
                            allFiles: context.allFiles
                        )
                    )
                }
            }
        }

        return violations
    }

    private func violation(
        package: String,
        shape: String,
        feature: String,
        having: Int,
        total: Int,
        allFiles: [String]
    ) -> Violation {
        let manifest = Paths.join(package, "Package.swift")
        let where_ = allFiles.contains(manifest) ? manifest : package
        let expected = Paths.join(package, PeerConsistencyRule.denormalise(feature, name: Paths.lastComponent(of: package)))
        let isDirectory = feature.hasSuffix("/")
        let noun = isDirectory ? "directory" : "file"

        return Violation(
            rule: identifier,
            severity: defaultSeverity,
            file: where_,
            line: nil,
            summary: "`\(Paths.lastComponent(of: package))` has no `\(feature)`, which \(having) of the "
                + "\(total) packages built the same way have "
                + "(\(PeerConsistencyRule.describe(shape)))",
            fix: "Add the \(noun) at `\(expected)`, or record why this one differs. Nothing declared this "
                + "convention — it is what the other \(having) already do, which is how conventions "
                + "usually exist. If the difference is deliberate, `consistency.ignore` in the "
                + "configuration is where to say so, and saying so is better than leaving the next "
                + "reader to wonder.",
            source: nil
        )
    }

    /// Every path inside a package, with the package's own name replaced by a
    /// wildcard so that `BagUnitTests` and `OrderUnitTests` are recognised as
    /// the same thing. Directories are included as well as files, and are
    /// marked with a trailing slash so that a missing folder and a missing file
    /// of the same name never collide.
    static func features(of package: String, in files: [String], ignoring: GlobSet) -> Set<String> {
        let name = Paths.lastComponent(of: package)
        var found: Set<String> = []

        for file in files where file.hasPrefix(package + "/") {
            guard !ignoring.matches(file) else { continue }
            let relative = String(file.dropFirst(package.count + 1))
            found.insert(normalise(relative, name: name))

            var segments = relative.split(separator: "/").map(String.init)
            while segments.count > 1 {
                segments.removeLast()
                found.insert(normalise(segments.joined(separator: "/"), name: name) + "/")
            }
        }

        return found
    }

    /// Drops any feature already implied by a missing ancestor directory.
    static func outermost(_ features: Set<String>) -> Set<String> {
        let directories = features.filter { $0.hasSuffix("/") }
        return features.filter { feature in
            !directories.contains { ancestor in
                ancestor != feature && feature.hasPrefix(ancestor)
            }
        }
    }

    /// A package's shape, as prose: the layers it is made of.
    static func describe(_ shape: String) -> String {
        let layers = shape.split(separator: "+").map { "`\($0)`" }
        guard layers.count > 1 else { return layers.joined() }
        return layers.dropLast().joined(separator: ", ") + " and " + layers.last!
    }

    static func normalise(_ path: String, name: String) -> String {
        guard !name.isEmpty else { return path }
        return path
            .split(separator: "/")
            .map { $0.replacingOccurrences(of: name, with: "*") }
            .joined(separator: "/")
    }

    static func denormalise(_ feature: String, name: String) -> String {
        let trimmed = feature.hasSuffix("/") ? String(feature.dropLast()) : feature
        return trimmed.replacingOccurrences(of: "*", with: name)
    }
}


/// Absences a project has already decided about.
struct ExemptionSet: Sendable {
    private let whole: GlobSet
    private let specific: [(package: Glob, feature: String)]

    init(_ entries: [String]) {
        var whole: [String] = []
        var specific: [(Glob, String)] = []
        for entry in entries {
            guard let separator = entry.lastIndex(of: ":") else {
                whole.append(entry)
                continue
            }
            specific.append((Glob(String(entry[entry.startIndex..<separator])),
                             String(entry[entry.index(after: separator)...])))
        }
        self.whole = GlobSet(whole)
        self.specific = specific
    }

    func covers(package: String, feature: String) -> Bool {
        if whole.matches(package) { return true }
        return specific.contains { $0.package.matches(package) && $0.feature == feature }
    }
}
