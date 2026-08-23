import Foundation

/// Decoding is written by hand rather than synthesised so that every field has
/// a default. A configuration that omits a key gets the considered answer for
/// that key; it does not fail to load. The alternative — demanding all fields —
/// makes the file grow with restatements of the obvious, and a file nobody
/// reads is a file nobody keeps true.
extension Configuration: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, name, exclude, roles, conventions, extensionBoundaries
        case frameworks, severities, disabledRules, enabledRules, consistency, tests
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try container.decodeIfPresent(Int.self, forKey: .version) ?? 1,
            name: try container.decodeIfPresent(String.self, forKey: .name),
            exclude: try container.decodeIfPresent([String].self, forKey: .exclude) ?? Configuration.defaultExclusions,
            roles: try container.decodeIfPresent([String: RoleDefinition].self, forKey: .roles) ?? [:],
            conventions: try container.decodeIfPresent([Convention].self, forKey: .conventions) ?? [],
            extensionBoundaries: try container.decodeIfPresent([ExtensionBoundary].self, forKey: .extensionBoundaries) ?? [],
            frameworks: try container.decodeIfPresent([String: [String]].self, forKey: .frameworks) ?? [:],
            severities: try container.decodeIfPresent([String: Severity].self, forKey: .severities) ?? [:],
            disabledRules: try container.decodeIfPresent([String].self, forKey: .disabledRules) ?? [],
            enabledRules: try container.decodeIfPresent([String].self, forKey: .enabledRules) ?? [],
            consistency: try container.decodeIfPresent(ConsistencySettings.self, forKey: .consistency)
                ?? ConsistencySettings(),
            tests: try container.decodeIfPresent(TestsConfiguration.self, forKey: .tests)
                ?? TestsConfiguration()
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(exclude, forKey: .exclude)
        try container.encode(roles, forKey: .roles)
        if !conventions.isEmpty { try container.encode(conventions, forKey: .conventions) }
        if !extensionBoundaries.isEmpty { try container.encode(extensionBoundaries, forKey: .extensionBoundaries) }
        if !frameworks.isEmpty { try container.encode(frameworks, forKey: .frameworks) }
        if !severities.isEmpty { try container.encode(severities, forKey: .severities) }
        if !disabledRules.isEmpty { try container.encode(disabledRules, forKey: .disabledRules) }
        if !enabledRules.isEmpty { try container.encode(enabledRules, forKey: .enabledRules) }
        try container.encode(consistency, forKey: .consistency)
        if !tests.isEmpty { try container.encode(tests, forKey: .tests) }
    }
}

extension RoleDefinition: Codable {
    private enum CodingKeys: String, CodingKey {
        case description, paths, targets, mayDependOn, sameRole
        case deniedFrameworks, allowsThirdParty, deniedSymbols, deniedNameSuffixes, reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            description: try container.decodeIfPresent(String.self, forKey: .description),
            paths: try container.decodeIfPresent([String].self, forKey: .paths) ?? [],
            targets: try container.decodeIfPresent([String].self, forKey: .targets) ?? [],
            mayDependOn: try container.decodeIfPresent([String].self, forKey: .mayDependOn) ?? [],
            sameRole: try container.decodeIfPresent(SameRolePolicy.self, forKey: .sameRole) ?? .allow,
            deniedFrameworks: try container.decodeIfPresent([String].self, forKey: .deniedFrameworks) ?? [],
            allowsThirdParty: try container.decodeIfPresent(Bool.self, forKey: .allowsThirdParty) ?? true,
            deniedSymbols: try container.decodeIfPresent([String].self, forKey: .deniedSymbols) ?? [],
            deniedNameSuffixes: try container.decodeIfPresent([String].self, forKey: .deniedNameSuffixes) ?? [],
            reason: try container.decodeIfPresent(String.self, forKey: .reason)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(description, forKey: .description)
        if !paths.isEmpty { try container.encode(paths, forKey: .paths) }
        if !targets.isEmpty { try container.encode(targets, forKey: .targets) }
        try container.encode(mayDependOn, forKey: .mayDependOn)
        try container.encode(sameRole, forKey: .sameRole)
        if !deniedFrameworks.isEmpty { try container.encode(deniedFrameworks, forKey: .deniedFrameworks) }
        try container.encode(allowsThirdParty, forKey: .allowsThirdParty)
        if !deniedSymbols.isEmpty { try container.encode(deniedSymbols, forKey: .deniedSymbols) }
        if !deniedNameSuffixes.isEmpty { try container.encode(deniedNameSuffixes, forKey: .deniedNameSuffixes) }
        try container.encodeIfPresent(reason, forKey: .reason)
    }
}

extension Convention: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, match, requireRole, exemptRoles, severity, reason, source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            match: try container.decode(ConventionMatch.self, forKey: .match),
            requireRole: try container.decodeIfPresent([Role].self, forKey: .requireRole) ?? [],
            exemptRoles: try container.decodeIfPresent([Role].self, forKey: .exemptRoles) ?? [.tests],
            severity: try container.decodeIfPresent(Severity.self, forKey: .severity),
            reason: try container.decodeIfPresent(String.self, forKey: .reason),
            source: try container.decodeIfPresent(String.self, forKey: .source)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(match, forKey: .match)
        try container.encode(requireRole, forKey: .requireRole)
        try container.encode(exemptRoles, forKey: .exemptRoles)
        try container.encodeIfPresent(severity, forKey: .severity)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encodeIfPresent(source, forKey: .source)
    }
}

extension ConventionMatch: Codable {
    private enum CodingKeys: String, CodingKey {
        case nameSuffix, namePrefix, nameMatches, kinds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            nameSuffix: try container.decodeIfPresent(String.self, forKey: .nameSuffix),
            namePrefix: try container.decodeIfPresent(String.self, forKey: .namePrefix),
            nameMatches: try container.decodeIfPresent(String.self, forKey: .nameMatches),
            kinds: try container.decodeIfPresent([DeclarationKind].self, forKey: .kinds)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(nameSuffix, forKey: .nameSuffix)
        try container.encodeIfPresent(namePrefix, forKey: .namePrefix)
        try container.encodeIfPresent(nameMatches, forKey: .nameMatches)
        try container.encodeIfPresent(kinds, forKey: .kinds)
    }
}

extension ExtensionBoundary: Codable {
    private enum CodingKeys: String, CodingKey {
        case from, declaredIn, reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            from: try container.decodeIfPresent([Role].self, forKey: .from) ?? [],
            declaredIn: try container.decodeIfPresent([Role].self, forKey: .declaredIn) ?? [],
            reason: try container.decodeIfPresent(String.self, forKey: .reason)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(from, forKey: .from)
        try container.encode(declaredIn, forKey: .declaredIn)
        try container.encodeIfPresent(reason, forKey: .reason)
    }
}
