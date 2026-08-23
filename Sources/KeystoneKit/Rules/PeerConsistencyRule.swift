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
public struct PeerConsistencyRule: Rule {
    public let identifier = "peer-consistency"
    public let defaultSeverity: Severity = .warning
    public var needsWholeProject: Bool { true }

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        let settings = context.configuration.consistency
        let ignored = GlobSet(settings.ignore)

        // Peers are packages sharing a parent directory: `Component/*` are
        // siblings, and so are `UI/*`, but a component and a feature are not.
        var groups: [String: [String]] = [:]
        for package in Set(context.graph.orderedModules.compactMap(\.packageDirectory)) where !package.isEmpty {
            groups[Paths.directory(of: package), default: []].append(package)
        }

        var violations: [Violation] = []

        for parent in groups.keys.sorted() {
            let peers = groups[parent]!.sorted()
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
                for feature in PeerConsistencyRule.outermost(absent).sorted() {
                    violations.append(
                        violation(
                            package: package,
                            parent: parent,
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
        parent: String,
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
                + "\(total) packages under `\(parent)/` have",
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
