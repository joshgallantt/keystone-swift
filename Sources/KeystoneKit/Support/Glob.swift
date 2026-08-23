import Foundation

/// A shell-style path pattern, compiled once and matched many times.
///
/// The dialect is the one every developer already knows from `.gitignore`
/// and SwiftPM: `*` stops at a path separator, `**` does not, and `**/`
/// matches any number of leading segments including none.
public struct Glob: Sendable, Hashable {
    public let pattern: String
    private let regex: NSRegularExpression

    public init(_ pattern: String) {
        self.pattern = pattern
        // A pattern is authored, not received, so a malformed one is a
        // programming error rather than input to be handled. Falling back to
        // a pattern that matches nothing keeps a typo from silently matching
        // everything, which is the failure that would go unnoticed.
        let source = Glob.regexSource(for: pattern)
        self.regex = (try? NSRegularExpression(pattern: source)) ?? Glob.matchesNothing
    }

    public func matches(_ path: String) -> Bool {
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        return regex.firstMatch(in: path, options: [], range: range) != nil
    }

    /// What each wildcard in the pattern stood for, left to right.
    ///
    /// This is what turns "wrong place" into "move it here". Matching
    /// `Component/Product/Sources/Data/Foo.swift` against the data layer's
    /// pattern yields `Product` and `Foo.swift`; substituting those into the
    /// domain layer's pattern names the exact directory the file should have
    /// been in. A rule that can say that is a rule someone can act on without
    /// first learning the architecture.
    public func captures(_ path: String) -> [String]? {
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        guard let match = regex.firstMatch(in: path, options: [], range: range) else { return nil }
        var found: [String] = []
        for group in 1..<match.numberOfRanges {
            guard let groupRange = Range(match.range(at: group), in: path) else {
                found.append("")
                continue
            }
            found.append(String(path[groupRange]))
        }
        return found
    }

    /// Rebuilds a pattern with its wildcards replaced in order. A pattern with
    /// more wildcards than there are captures keeps the rest as literal `*`,
    /// which reads as "any" and is honest about what is not known.
    public static func fill(_ pattern: String, with captures: [String]) -> String {
        var out = ""
        var remaining = captures[...]
        var index = pattern.startIndex

        while index < pattern.endIndex {
            let character = pattern[index]
            if character == "*" {
                let next = pattern.index(after: index)
                let isDoubled = next < pattern.endIndex && pattern[next] == "*"
                if let value = remaining.first {
                    remaining = remaining.dropFirst()
                    out += value
                } else {
                    out += isDoubled ? "**" : "*"
                }
                index = isDoubled ? pattern.index(after: next) : next
                continue
            }
            out.append(character)
            index = pattern.index(after: index)
        }

        return out
    }

    private static let matchesNothing = try! NSRegularExpression(pattern: "(?!)")

    static func regexSource(for pattern: String) -> String {
        var out = "^"
        let characters = Array(pattern)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "*" {
                let isDoubled = index + 1 < characters.count && characters[index + 1] == "*"
                if isDoubled {
                    let isSegment = index + 2 < characters.count && characters[index + 2] == "/"
                    if isSegment {
                        // `**/` absorbs the separator so that `**/Tests/**`
                        // also claims a `Tests/` directory at the root.
                        out += "((?:.*/)?)"
                        index += 3
                    } else {
                        out += "(.*)"
                        index += 2
                    }
                } else {
                    out += "([^/]*)"
                    index += 1
                }
                continue
            }

            if character == "?" {
                out += "([^/])"
                index += 1
                continue
            }

            if "\\.()+|^$@%{}[]".contains(character) {
                out += "\\\(character)"
                index += 1
                continue
            }

            out.append(character)
            index += 1
        }

        return out + "$"
    }
}

/// A union of patterns. Empty matches nothing, which is what a role with no
/// declared paths should do — a role that claims every file by accident is
/// worse than one that claims none.
public struct GlobSet: Sendable {
    public let globs: [Glob]

    public init(_ patterns: [String]) {
        self.globs = patterns.map(Glob.init)
    }

    public var isEmpty: Bool { globs.isEmpty }

    public func matches(_ path: String) -> Bool {
        globs.contains { $0.matches(path) }
    }

    /// The pattern that claimed the path, for reports that must say why.
    public func firstMatch(_ path: String) -> String? {
        globs.first { $0.matches(path) }?.pattern
    }

    public func matchingGlob(_ path: String) -> Glob? {
        globs.first { $0.matches(path) }
    }
}
