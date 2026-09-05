import Foundation

/// How this project tests, stated once.
///
/// Two tiers answer different questions and are written by different people in
/// different languages. An acceptance failure says *the thing this software is for stopped working*; a unit
/// failure says *which rule is wrong*. A codebase with only one of them can
/// answer only one of those, and which one it has usually happened by accident.
public struct TestsConfiguration: Sendable, Codable {
    public var tiers: [TestTier]
    /// The directory inside a tier that holds everything which is not a test.
    /// This split is what makes "is this a test or a helper" a decidable
    /// question, and every other rule here depends on it being answerable.
    public var supportDirectory: String
    /// Meszaros' taxonomy, as name prefixes. The kind is part of the name
    /// because the kind says which verification style is in play: a stub
    /// supports checking state, a spy or a mock supports checking behaviour.
    public var doublePrefixes: [String]

    public init(
        tiers: [TestTier] = [],
        supportDirectory: String = "Support",
        doublePrefixes: [String] = ["Stub", "Spy", "Mock", "Fake", "Dummy", "InMemory"]
    ) {
        self.tiers = tiers
        self.supportDirectory = supportDirectory
        self.doublePrefixes = doublePrefixes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = TestsConfiguration()
        self.init(
            tiers: try container.decodeIfPresent([TestTier].self, forKey: .tiers) ?? [],
            supportDirectory: try container.decodeIfPresent(String.self, forKey: .supportDirectory)
                ?? defaults.supportDirectory,
            doublePrefixes: try container.decodeIfPresent([String].self, forKey: .doublePrefixes)
                ?? defaults.doublePrefixes
        )
    }

    public var isEmpty: Bool { tiers.isEmpty }

    public func tier(named name: String) -> TestTier? {
        tiers.first { $0.name == name }
    }

    /// Which tier claims a file, if any.
    public func tier(forFile path: String) -> TestTier? {
        tiers.first { GlobSet($0.paths).matches(path) }
    }

    /// Whether a path is helper code rather than a test. Matched as a path
    /// segment so that a file merely called `Supporting.swift` is still a test.
    public func isSupport(_ path: String) -> Bool {
        path.split(separator: "/").contains { $0 == supportDirectory }
    }

    public func isDouble(_ name: String) -> Bool {
        doublePrefixes.contains { name.hasPrefix($0) && name.count > $0.count }
    }
}

public struct TestTier: Sendable, Codable {
    public var name: String
    public var paths: [String]
    /// Whether every test in this tier must carry a sentence as its name.
    public var namesReadAsProse: Bool
    /// Layers whose types this tier may not mention. Stated as roles rather
    /// than as names, so a driver called `Store` is permitted while a
    /// persistence type called `WishlistStore` is not — a distinction a
    /// pattern over names cannot make.
    public var mayNotReference: [Role]
    /// A directory of recorded output this tier is meaningless without.
    public var artifactDirectory: String?
    public var reason: String?

    public init(
        name: String,
        paths: [String],
        namesReadAsProse: Bool = false,
        mayNotReference: [Role] = [],
        artifactDirectory: String? = nil,
        reason: String? = nil
    ) {
        self.name = name
        self.paths = paths
        self.namesReadAsProse = namesReadAsProse
        self.mayNotReference = mayNotReference
        self.artifactDirectory = artifactDirectory
        self.reason = reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            paths: try container.decodeIfPresent([String].self, forKey: .paths) ?? [],
            namesReadAsProse: try container.decodeIfPresent(Bool.self, forKey: .namesReadAsProse) ?? false,
            mayNotReference: try container.decodeIfPresent([Role].self, forKey: .mayNotReference) ?? [],
            artifactDirectory: try container.decodeIfPresent(String.self, forKey: .artifactDirectory),
            reason: try container.decodeIfPresent(String.self, forKey: .reason)
        )
    }
}

/// A condition under which a package owes a tier.
///
