import Foundation

/// Repository-relative POSIX paths, used everywhere a path is stored or shown.
///
/// One representation throughout means a violation reads the same in the
/// terminal, in JSON, in a hook payload and in CI, and that two runs on two
/// machines produce byte-identical reports.
public enum Paths {
    public static func relative(_ absolute: String, to root: String) -> String {
        let normalisedRoot = root.hasSuffix("/") ? String(root.dropLast()) : root
        guard absolute.hasPrefix(normalisedRoot + "/") else { return absolute }
        return String(absolute.dropFirst(normalisedRoot.count + 1))
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
