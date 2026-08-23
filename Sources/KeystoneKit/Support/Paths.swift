import Foundation

/// Repository-relative POSIX paths, used everywhere a path is stored or shown.
///
/// One representation throughout means a violation reads the same in the
/// terminal, in JSON, in a hook payload and in CI, and that two runs on two
/// machines produce byte-identical reports.
public enum Paths {
    /// Tidies a path without trying to resolve it.
    ///
    /// Symlink resolution is deliberately *not* done here — see `variants`.
    public static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    public static func relative(_ absolute: String, to root: String) -> String {
        for candidate in variants(of: root) {
            let normalised = candidate.hasSuffix("/") ? String(candidate.dropLast()) : candidate
            if absolute == normalised { return "" }
            if absolute.hasPrefix(normalised + "/") {
                return String(absolute.dropFirst(normalised.count + 1))
            }
        }
        return absolute
    }

    /// The two spellings macOS uses for the same directory.
    ///
    /// `/var` is a symlink to `/private/var`, and Foundation is inconsistent
    /// about which it hands back: the directory enumerator yields
    /// `/private/var/...`, while both `standardizedFileURL` and
    /// `resolvingSymlinksInPath` strip the `/private` off again. Canonicalising
    /// through either of them therefore cannot make the two sides agree — the
    /// root came out `/var/...` and every file came out `/private/var/...`, no
    /// prefix matched, and every path stayed absolute. Globs then matched
    /// nothing and a correct project was reported as having no architecture at
    /// all: a silent, total false negative, and the most dangerous shape of bug
    /// this tool can have. Comparing against both spellings is cheap string
    /// work and cannot drift.
    static func variants(of path: String) -> [String] {
        let privatePrefix = "/private"
        if path.hasPrefix(privatePrefix + "/") {
            return [path, String(path.dropFirst(privatePrefix.count))]
        }
        return [path, privatePrefix + path]
    }

    public static func absolute(_ relative: String, in root: String) -> String {
        if relative.hasPrefix("/") { return relative }
        let normalisedRoot = root.hasSuffix("/") ? String(root.dropLast()) : root
        return relative.isEmpty ? normalisedRoot : normalisedRoot + "/" + relative
    }

    public static func join(_ components: String...) -> String {
        components
            .filter { !$0.isEmpty && $0 != "." }
            .joined(separator: "/")
            .replacingOccurrences(of: "//", with: "/")
    }

    /// Resolves `..` and `.` without touching the file system, so a manifest
    /// that points at a sibling package still yields a path we can compare.
    public static func normalise(_ path: String) -> String {
        let isAbsolute = path.hasPrefix("/")
        var stack: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                if let last = stack.last, last != ".." {
                    stack.removeLast()
                } else if !isAbsolute {
                    stack.append("..")
                }
            default:
                stack.append(String(component))
            }
        }
        return (isAbsolute ? "/" : "") + stack.joined(separator: "/")
    }

    public static func directory(of path: String) -> String {
        guard let index = path.lastIndex(of: "/") else { return "" }
        return String(path[path.startIndex..<index])
    }

    public static func lastComponent(of path: String) -> String {
        guard let index = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: index)...])
    }
}
