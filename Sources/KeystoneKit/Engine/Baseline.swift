import Foundation

/// The violations a project has agreed to live with for now.
///
/// Without this, adopting the tool on an existing app means a first run with
/// two thousand errors, which is indistinguishable from no signal at all. With
/// it, the first run records the debt and the tool goes quiet — and from that
/// moment nothing new gets in, while the recorded number only ever falls. That
/// is the whole migration strategy: hold the line, then move it.
public struct Baseline: Sendable, Codable {
    public struct Entry: Sendable, Codable, Hashable {
        public var rule: String
        public var file: String
        public var summary: String

        public init(rule: String, file: String, summary: String) {
            self.rule = rule
            self.file = file
            self.summary = summary
        }
    }

    public var version: Int
    public var entries: [Entry]

    public init(version: Int = 1, entries: [Entry] = []) {
        self.version = version
        self.entries = entries
    }

    /// Line numbers are deliberately not part of an entry's identity. Editing
    /// the top of a file would otherwise resurrect every accepted violation
    /// below it, and a baseline that churns is a baseline people delete.
    public static func entry(for violation: Violation) -> Entry {
        Entry(rule: violation.rule, file: violation.file, summary: violation.summary)
    }

    public static func record(_ violations: [Violation]) -> Baseline {
        let entries = Set(violations.map(entry(for:)))
        return Baseline(
            entries: entries.sorted {
                $0.file == $1.file
                    ? ($0.rule == $1.rule ? $0.summary < $1.summary : $0.rule < $1.rule)
                    : $0.file < $1.file
            }
        )
    }

    /// Splits a run into what is new and what was already known.
    public func partition(_ violations: [Violation]) -> (fresh: [Violation], accepted: [Violation]) {
        let known = Set(entries)
        var fresh: [Violation] = []
        var accepted: [Violation] = []

        for violation in violations {
            if known.contains(Baseline.entry(for: violation)) {
                accepted.append(violation)
            } else {
                fresh.append(violation)
            }
        }
        return (fresh, accepted)
    }

    /// Entries no longer produced by the code. Reporting these is what turns a
    /// baseline from a place debt hides into a record of progress.
    public func resolved(against violations: [Violation]) -> [Entry] {
        let current = Set(violations.map(Baseline.entry(for:)))
        return entries.filter { !current.contains($0) }
    }
}
