import Foundation

/// Turns a list of real directories into the patterns a person would have
/// written by hand.
///
/// A generated configuration listing forty literal directories is technically
/// correct and practically dead: nobody maintains it, and the first new
/// component silently falls outside the architecture. A pattern survives the
/// next component, which is the only version of this file worth committing.
///
/// The work is done in two moves. Each directory is first widened to the
/// shortest ancestor that no other layer lives under — which is what turns
/// `Component/Bag/Sources/Domain/Model` into `Component/Bag/Sources/Domain`.
/// Those are then merged across components by wildcarding whatever differs,
/// and every merge is checked against the other layers before it is kept, so
/// a pattern can never quietly claim a directory belonging to somebody else.
public enum PathGeneralizer {
    public static func generalize(
        _ directories: [String],
        avoiding others: [String],
        packages: Set<String> = []
    ) -> [String] {
        let own = Array(Set(directories)).sorted()
        guard !own.isEmpty else { return [] }
        let foreign = Set(others)

        let widened = removeDescendants(Array(Set(own.map { widen($0, avoiding: foreign) })).sorted())

        var patterns: Set<String> = []
        for group in groupedByDepth(widened) {
            patterns.formUnion(merge(group, avoiding: foreign, packages: packages))
        }
        return patterns.sorted()
    }

    /// The shortest ancestor of `directory` that no other layer occupies.
    static func widen(_ directory: String, avoiding others: Set<String>) -> String {
        let segments = directory.split(separator: "/").map(String.init)
        for length in 1...segments.count {
            let candidate = segments.prefix(length).joined(separator: "/")
            let taken = others.contains { $0 == candidate || $0.hasPrefix(candidate + "/") }
            if !taken { return candidate }
        }
        return directory
    }

    static func removeDescendants(_ directories: [String]) -> [String] {
        directories.filter { candidate in
            !directories.contains { other in other != candidate && candidate.hasPrefix(other + "/") }
        }
    }

    static func groupedByDepth(_ directories: [String]) -> [[String]] {
        var groups: [Int: [String]] = [:]
        for directory in directories {
            groups[directory.split(separator: "/").count, default: []].append(directory)
        }
        return groups.keys.sorted().map { groups[$0]!.sorted() }
    }

    /// Merge as far as the other layers allow, and no further.
    ///
    /// The whole group is tried first. If the resulting pattern would reach
    /// into another layer, the group is split by its last segment and each part
    /// tried again — which is how `UI/*/Sources/UI` survives while
    /// `UI/*/Sources/*` is rejected for swallowing `Sources/DI`.
    static func merge(_ group: [String], avoiding others: Set<String>, packages: Set<String>) -> [String] {
        // Widest first, and each fallback gives up one degree of generality.
        // Treating package names as variables is the first thing dropped,
        // because a pattern that reaches into another layer is worse than one
        // that will need editing when a package is added.
        if let whole = firstSafePattern(for: group, avoiding: others, packages: packages) {
            return [whole]
        }

        var byLastSegment: [String: [String]] = [:]
        for directory in group {
            byLastSegment[String(directory.split(separator: "/").last ?? ""), default: []].append(directory)
        }

        var results: [String] = []
        for key in byLastSegment.keys.sorted() {
            let subgroup = byLastSegment[key]!
            if let narrowed = firstSafePattern(for: subgroup, avoiding: others, packages: packages) {
                results.append(narrowed)
            } else {
                results.append(contentsOf: subgroup.map { pattern(for: [$0], avoiding: others, packages: []) })
            }
        }
        return results
    }

    static func firstSafePattern(
        for group: [String],
        avoiding others: Set<String>,
        packages: Set<String>
    ) -> String? {
        for attempt in [packages, []] {
            let candidate = pattern(for: group, avoiding: others, packages: attempt)
            if !collides(candidate, with: others) { return candidate }
        }
        return nil
    }

    static func pattern(for group: [String], avoiding others: Set<String>, packages: Set<String>) -> String {
        let split = group.map { $0.split(separator: "/").map(String.init) }
        guard let first = split.first else { return "" }

        var segments: [String] = []
        for index in first.indices {
            let values = Set(split.map { $0[index] })
            if values.count > 1 {
                segments.append("*")
                continue
            }
            // A segment that names a package is a variable even when there is
            // only one of them today. Without this, a project with a single
            // component gets `Component/Catalog/Sources/Domain/**`, and the
            // second component silently falls outside the architecture. The
            // `unclassified-files` rule would eventually say so, but the
            // configuration should have been right in the first place.
            let prefix = first.prefix(index + 1).joined(separator: "/")
            segments.append(packages.contains(prefix) ? "*" : first[index])
        }

        let base = segments.joined(separator: "/")

        // When another layer lives *inside* one of these directories, claiming
        // the subtree would swallow it. Claim the directory's own files only.
        let nested = group.contains { directory in
            others.contains { $0.hasPrefix(directory + "/") }
        }
        return base + (nested ? "/*" : "/**")
    }

    /// Whether a pattern would claim a file belonging to another layer.
    static func collides(_ pattern: String, with others: Set<String>) -> Bool {
        let glob = Glob(pattern)
        return others.contains { glob.matches($0 + "/probe.swift") }
    }
}
