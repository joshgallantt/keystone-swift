import Foundation

/// The whole of what this tool believes about a project.
///
/// Everything the checker does is a function of this value and the files on
/// disk. Nothing is inferred at check time — inference happens once, in
/// `init`, and its output is this file, in the repository, reviewable in a
/// pull request. That separation is what makes two runs agree.
public struct Configuration: Sendable {
    public var version: Int
    public var name: String?
    public var exclude: [String]
    public var roles: [String: RoleDefinition]
    public var conventions: [Convention]
    public var extensionBoundaries: [ExtensionBoundary]
    public var frameworks: [String: [String]]
    public var severities: [String: Severity]
    public var disabledRules: [String]
    /// When non-empty, the only rules that run. SwiftLint's `only_rules`, and
    /// for the same reason: a team adopting this on a large codebase wants to
    /// turn on three rules and mean them, not turn off twenty-six and argue
    /// about each. Empty means every rule, which is what a new project wants.
    public var enabledRules: [String]
    public var consistency: ConsistencySettings
    public var tests: TestsConfiguration

    public init(
        version: Int = 1,
        name: String? = nil,
        exclude: [String] = Configuration.defaultExclusions,
        roles: [String: RoleDefinition] = [:],
        conventions: [Convention] = [],
        extensionBoundaries: [ExtensionBoundary] = [],
        frameworks: [String: [String]] = [:],
        severities: [String: Severity] = [:],
        disabledRules: [String] = [],
        enabledRules: [String] = [],
        consistency: ConsistencySettings = ConsistencySettings(),
        tests: TestsConfiguration = TestsConfiguration()
    ) {
        self.version = version
        self.name = name
        self.exclude = exclude
        self.roles = roles
        self.conventions = conventions
        self.extensionBoundaries = extensionBoundaries
        self.frameworks = frameworks
        self.severities = severities
        self.disabledRules = disabledRules
        self.enabledRules = enabledRules
        self.consistency = consistency
        self.tests = tests
    }

    /// Build output, dependency checkouts and vendored code. A project can
    /// replace this list, but it starts non-empty because a tool that reports
    /// three thousand violations inside `.build` on first run teaches the user
    /// to ignore it.
    public static let defaultExclusions = [
        "**/.build/**",
        "**/build/**",
        "**/DerivedData/**",
        "**/.swiftpm/**",
        "**/Pods/**",
        "**/Carthage/**",
        "**/vendor/**",
        "**/*.generated.swift",
        "**/Generated/**"
    ]

    public var catalog: FrameworkCatalog {
        FrameworkCatalog(overrides: frameworks)
    }

    /// Roles in a fixed order, so reports and generated documents do not
    /// reshuffle themselves between runs of the same input.
    public var orderedRoles: [(name: Role, definition: RoleDefinition)] {
        roles.keys.map(Role.init).sorted().map { ($0, roles[$0.rawValue]!) }
    }

    public func definition(for role: Role) -> RoleDefinition? {
        roles[role.rawValue]
    }

    public func severity(for rule: String, default fallback: Severity) -> Severity {
        severities[rule] ?? fallback
    }

    public func isEnabled(_ rule: String) -> Bool {
        guard !disabledRules.contains(rule) else { return false }
        return enabledRules.isEmpty || enabledRules.contains(rule)
    }
}

/// What one layer is allowed to do. Every boundary rule reads these fields;
/// none reads a role's name. Rename `domain` to `core` throughout and the
/// tool behaves identically.
public struct RoleDefinition: Sendable {
    public var description: String?
    /// Path patterns claiming files for this role. These win over `targets`,
    /// because a path is a statement about this repository while a target
    /// name is a guess about a convention.
    public var paths: [String]
    /// Target-name patterns claiming whole modules for this role.
    public var targets: [String]
    /// Role names this role may reach. The single entry `*` means anything,
    /// which is what a composition root is *for*.
    public var mayDependOn: [String]
    public var sameRole: SameRolePolicy
    /// Framework categories from `FrameworkCatalog` this role refuses.
    public var deniedFrameworks: [String]
    public var allowsThirdParty: Bool
    /// Type names this role must not mention even when the module that
    /// declares them is permitted — the escape hatch for frameworks that
    /// smuggle capability inside an allowed umbrella, `URLSession` inside
    /// `Foundation` being the standing example.
    public var deniedSymbols: [String]
    /// Name endings that belong to another layer's vocabulary. A domain that
    /// declares a `*Client` has borrowed a word from the layer that owns the
    /// wire, and the borrowing is usually how the responsibility follows.
    public var deniedNameSuffixes: [String]
    /// Printed when this role's boundary is crossed. Write the correction and
    /// where the code should go instead, not a restatement of the rule.
    public var reason: String?

    public init(
        description: String? = nil,
        paths: [String] = [],
        targets: [String] = [],
        mayDependOn: [String] = [],
        sameRole: SameRolePolicy = .allow,
        deniedFrameworks: [String] = [],
        allowsThirdParty: Bool = true,
        deniedSymbols: [String] = [],
        deniedNameSuffixes: [String] = [],
        reason: String? = nil
    ) {
        self.description = description
        self.paths = paths
        self.targets = targets
        self.mayDependOn = mayDependOn
        self.sameRole = sameRole
        self.deniedFrameworks = deniedFrameworks
        self.allowsThirdParty = allowsThirdParty
        self.deniedSymbols = deniedSymbols
        self.deniedNameSuffixes = deniedNameSuffixes
        self.reason = reason
    }

    public var dependsOnAnything: Bool {
        mayDependOn.contains("*")
    }

    public func mayDepend(on role: Role) -> Bool {
        dependsOnAnything || mayDependOn.contains(role.rawValue)
    }
}

public enum DeclarationKind: String, Codable, Sendable, CaseIterable {
    case `protocol`
    case `struct`
    case `class`
    case `actor`
    case `enum`
    case `extension`
    case typealias_ = "typealias"
    case function
    case variable
}

/// A naming convention tied to a place. `*Repository` as a protocol belongs to
/// the domain; the same suffix on a struct belongs to data. Stating both is
/// how a convention becomes a boundary rather than a style note.
public struct Convention: Sendable {
    public var name: String
    public var match: ConventionMatch
    public var requireRole: [Role]
    public var exemptRoles: [Role]
    public var severity: Severity?
    public var reason: String?
    public var source: String?

    public init(
        name: String,
        match: ConventionMatch,
        requireRole: [Role],
        exemptRoles: [Role] = [.tests],
        severity: Severity? = nil,
        reason: String? = nil,
        source: String? = nil
    ) {
        self.name = name
        self.match = match
        self.requireRole = requireRole
        self.exemptRoles = exemptRoles
        self.severity = severity
        self.reason = reason
        self.source = source
    }
}

public struct ConventionMatch: Sendable {
    public var nameSuffix: String?
    public var namePrefix: String?
    public var nameMatches: String?
    public var kinds: [DeclarationKind]?

    public init(
        nameSuffix: String? = nil,
        namePrefix: String? = nil,
        nameMatches: String? = nil,
        kinds: [DeclarationKind]? = nil
    ) {
        self.nameSuffix = nameSuffix
        self.namePrefix = namePrefix
        self.nameMatches = nameMatches
        self.kinds = kinds
    }
}

/// Which roles may not reopen which other roles' types.
///
/// An extension gives one type a different surface depending on which module
/// is looking at it, which is how a business rule ends up with two homes and
/// no owner. Stated between roles, this survives any renaming of the types
/// involved — the reason it replaces a list of forbidden type names.
public struct ExtensionBoundary: Sendable {
    public var from: [Role]
    public var declaredIn: [Role]
    public var reason: String?

    public init(from: [Role], declaredIn: [Role], reason: String? = nil) {
        self.from = from
        self.declaredIn = declaredIn
        self.reason = reason
    }
}


/// How alike sibling modules are expected to be.
///
/// Not every convention in a codebase is written down. Most are held in the
/// shape of the thing: nine components have a test fixture file and the tenth
/// does not, and nobody decided that — it just never got added. Comparing peers
/// against each other finds those, which a rule written in advance never could,
/// because nobody knew the convention existed until it was broken.
public struct ConsistencySettings: Sendable, Codable {
    /// How many siblings a group needs before its shape means anything. Two
    /// packages disagreeing is not a convention with an exception; it is two
    /// packages.
    public var minimumPeers: Int
    /// The share of siblings that must have something before its absence
    /// elsewhere is worth reporting.
    public var threshold: Double
    /// Paths never compared — build output, lockfiles, anything whose presence
    /// is incidental rather than a decision.
    public var ignore: [String]

    public init(
        minimumPeers: Int = 3,
        threshold: Double = 0.75,
        ignore: [String] = ["**/*.resolved", "**/.DS_Store", "**/*.plist", "**/*.xcscheme"]
    ) {
        self.minimumPeers = minimumPeers
        self.threshold = threshold
        self.ignore = ignore
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ConsistencySettings()
        self.init(
            minimumPeers: try container.decodeIfPresent(Int.self, forKey: .minimumPeers) ?? defaults.minimumPeers,
            threshold: try container.decodeIfPresent(Double.self, forKey: .threshold) ?? defaults.threshold,
            ignore: try container.decodeIfPresent([String].self, forKey: .ignore) ?? defaults.ignore
        )
    }
}
