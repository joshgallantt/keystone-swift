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

        // Widen only where it buys something. A directory that already looks
        // like its siblings — same depth, same final segment — is left alone,
        // because widening it would take it out of the group it belongs to.
        // `Component/Money/Sources/Domain` has no `Data` or `DI` beside it, so
        // widening happily swallowed the whole of `Sources` and produced a rule
        // naming Money in particular, when the pattern the other nine already
        // matched was right there.
        let resolved = own.map { directory -> String in
            hasSibling(directory, in: own) ? directory : widen(directory, avoiding: foreign)
        }
        let widened = removeDescendants(Array(Set(resolved)).sorted())

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

    /// Whether another directory sits at the same depth under the same final
    /// name, which is what makes two paths one rule rather than two.
    static func hasSibling(_ directory: String, in all: [String]) -> Bool {
        let segments = directory.split(separator: "/")
        return all.contains { other in
            guard other != directory else { return false }
            let theirs = other.split(separator: "/")
            return theirs.count == segments.count && theirs.last == segments.last
        }
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

        // Cluster by the last two characters of the final segment. Names that
        // end alike usually are alike, and this is what lets the `*UIHost`
        // directories merge with each other while `Navigation` stays on its
        // own — splitting straight to one group per name would have made the
        // shared ending invisible.
        var byLastSegment: [String: [String]] = [:]
        for directory in group {
            let last = String(directory.split(separator: "/").last ?? "")
            byLastSegment[String(last.suffix(2)), default: []].append(directory)
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

            // A segment that names a package is a variable even when there is
            // only one of them today. Without this, a project with a single
            // component gets `Component/Catalog/Sources/Domain/**`, and the
            // second component silently falls outside the architecture.
            let isPackage = split.contains { packages.contains($0.prefix(index + 1).joined(separator: "/")) }
            if isPackage {
                segments.append("*")
                continue
            }

            if values.count == 1 {
                segments.append(first[index])
                continue
            }

            // Differing segments usually share the part that means something:
            // `AuthUIHost`, `SheetUIHost` and `SnackbarUIHost` are one idea
            // spelled three ways. Emitting `*UIHost` says that; enumerating
            // them writes this project's module names into a rule, which is
            // the roster problem the whole design exists to avoid.
            segments.append(affix(values) ?? "*")
        }

        let base = segments.joined(separator: "/")

        // When another layer lives *inside* one of these directories, claiming
        // the subtree would swallow it. Claim the directory's own files only.
        let nested = group.contains { directory in
            others.contains { $0.hasPrefix(directory + "/") }
        }
        return base + (nested ? "/*" : "/**")
    }

    /// A wildcard that keeps the part these names have in common.
    ///
    /// Accepted only when the shared part is long enough to mean something —
    /// three characters, or a whole name in its own right, which is what makes
    /// `*UI` legitimate across `UI` and `AuthUI` while `*ns` across `Screens`
    /// and `Tokens` is rejected as a coincidence of spelling.
    static func affix(_ values: Set<String>) -> String? {
        let names = values.sorted()
        guard names.count > 1, let shortest = names.map(\.count).min(), shortest > 0 else { return nil }

        var suffix = ""
        for length in 1...shortest {
            let candidate = String(names[0].suffix(length))
            guard names.allSatisfy({ $0.hasSuffix(candidate) }) else { break }
            suffix = candidate
        }
        if suffix.count >= 3 || (suffix.count >= 2 && names.contains(suffix)) {
            return "*" + suffix
        }

        var prefix = ""
        for length in 1...shortest {
            let candidate = String(names[0].prefix(length))
            guard names.allSatisfy({ $0.hasPrefix(candidate) }) else { break }
            prefix = candidate
        }
        if prefix.count >= 3 || (prefix.count >= 2 && names.contains(prefix)) {
            return prefix + "*"
        }

        return nil
    }

    /// Whether a pattern would claim a file belonging to another layer.
    static func collides(_ pattern: String, with others: Set<String>) -> Bool {
        let glob = Glob(pattern)
        return others.contains { glob.matches($0 + "/probe.swift") }
    }
}
