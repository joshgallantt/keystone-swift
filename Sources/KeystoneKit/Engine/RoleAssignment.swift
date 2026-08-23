import Foundation

/// Which role every file and every module belongs to.
///
/// Layout is *derived*, not configured. A rule like "the domain may not import
/// storage" is architecture and belongs in a manifest; a path like
/// `Component/*/Sources/Domain/**` is a description of one repository, and a
/// tool that needs that written down before it works is not project-agnostic —
/// it is project-agnostic once configured, which is a different and much weaker
/// claim.
///
/// So roles come from evidence the repository already carries: what its
/// directories are called, what the build system says each target is, and what
/// depends on what. A project whose layout this cannot read declares `paths`
/// for the role in question and those win outright — an override for the
/// unusual case rather than a prerequisite for the usual one.
///
/// The evidence deliberately excludes anything inside the files. Import
/// statements would classify better, but they are only available when every
/// file has been parsed, and the pre-write hook parses exactly one. A role that
/// meant different things in the hook and in CI would be worse than a role that
/// is occasionally unsure.
public struct RoleAssignment: Sendable {
    public let fileRoles: [String: Role]
    public let moduleRoles: [String: Role]
    public let unclassifiedFiles: [String]
    /// How each module was placed, for reports that must show their working.
    public let evidence: [String: String]

    private let configuration: Configuration

    public init(configuration: Configuration, graph: ProjectGraph, swiftFiles: [String]) {
        self.configuration = configuration

        let declared = configuration.orderedRoles
            .filter { !$0.definition.paths.isEmpty }
            .map { ($0.name, GlobSet($0.definition.paths)) }
        let targetClaims = configuration.orderedRoles
            .filter { !$0.definition.targets.isEmpty }
            .map { ($0.name, GlobSet($0.definition.targets)) }
        let known = Set(configuration.roles.keys)

        // Declared paths win outright.
        var fileRoles: [String: Role] = [:]
        for file in swiftFiles {
            if let role = RoleAssignment.mostSpecific(claims: declared, subject: file) {
                fileRoles[file] = role
            }
        }

        // Then what the directories call themselves.
        for file in swiftFiles where fileRoles[file] == nil {
            guard let match = LayerVocabulary.match(forDirectory: Paths.directory(of: file)),
                  known.contains(match.role.rawValue) else { continue }
            fileRoles[file] = match.role
        }

        var filesByModule: [String: [String]] = [:]
        for file in swiftFiles {
            guard let module = graph.module(owning: file) else { continue }
            filesByModule[module.name, default: []].append(file)
        }

        var moduleRoles: [String: Role] = [:]
        var evidence: [String: String] = [:]

        for module in graph.orderedModules {
            if let role = RoleAssignment.mostSpecific(claims: targetClaims, subject: module.name) {
                moduleRoles[module.name] = role
                evidence[module.name] = "named by the configuration"
                continue
            }
            if module.kind.isTest, known.contains(Role.tests.rawValue) {
                moduleRoles[module.name] = .tests
                evidence[module.name] = "test target"
                continue
            }
            if module.kind == .app, known.contains(Role.composition.rawValue) {
                moduleRoles[module.name] = .composition
                evidence[module.name] = "application target"
                continue
            }
            if let match = module.sourceRoots.lazy.compactMap(LayerVocabulary.match(forDirectory:)).first,
               known.contains(match.role.rawValue) {
                moduleRoles[module.name] = match.role
                evidence[module.name] = "directory named `\(match.segment)`"
                continue
            }
            if let modal = RoleAssignment.modal((filesByModule[module.name] ?? []).compactMap { fileRoles[$0] }) {
                moduleRoles[module.name] = modal
                evidence[module.name] = "most of its files are `\(modal)`"
            }
        }

        // What is left is placed by what it depends on. A module that reaches
        // both a domain and a data module is wiring them together, whatever it
        // is called.
        for module in graph.orderedModules where moduleRoles[module.name] == nil {
            let reached = Set((graph.edges[module.name] ?? []).compactMap { moduleRoles[$0] })
            guard let (role, why) = RoleAssignment.fromShape(reached, isLeaf: (graph.edges[module.name] ?? []).isEmpty),
                  known.contains(role.rawValue) else { continue }
            moduleRoles[module.name] = role
            evidence[module.name] = why
        }

        var unclassified: [String] = []
        for file in swiftFiles where fileRoles[file] == nil {
            if let module = graph.module(owning: file), let role = moduleRoles[module.name] {
                fileRoles[file] = role
            } else {
                unclassified.append(file)
            }
        }

        self.fileRoles = fileRoles
        self.moduleRoles = moduleRoles
        self.unclassifiedFiles = unclassified.sorted()
        self.evidence = evidence
    }

    public func role(ofFile path: String) -> Role? { fileRoles[path] }
    public func role(ofModule name: String) -> Role? { moduleRoles[name] }

    public func definition(ofFile path: String) -> RoleDefinition? {
        role(ofFile: path).flatMap { configuration.definition(for: $0) }
    }

    static func fromShape(_ reached: Set<Role>, isLeaf: Bool) -> (Role, String)? {
        if reached.contains(.domain) && reached.contains(.data) {
            return (.composition, "depends on both a domain and a data module")
        }
        if reached.contains(.presentation) {
            return (.composition, "depends on a presentation module")
        }
        if reached.contains(.domain) {
            return (.data, "depends on a domain module without being a screen")
        }
        if isLeaf {
            return (.domain, "depends on nothing, so it is a candidate for the stable centre")
        }
        return (.domain, "no clear evidence — review this one")
    }

    /// The claim with the most literal characters wins, so a specific override
    /// beats a general one without either having to say which matters more.
    static func mostSpecific(claims: [(Role, GlobSet)], subject: String) -> Role? {
        var winner: Role?
        var bestScore = -1
        for (role, globs) in claims {
            guard let pattern = globs.firstMatch(subject) else { continue }
            let score = pattern.filter { $0 != "*" && $0 != "?" }.count
            if score > bestScore {
                bestScore = score
                winner = role
            }
        }
        return winner
    }

    /// Ties break toward the role that sorts first, so a module split evenly
    /// lands somewhere predictable rather than somewhere that depends on
    /// file-system ordering.
    static func modal(_ roles: [Role]) -> Role? {
        guard !roles.isEmpty else { return nil }
        var counts: [Role: Int] = [:]
        for role in roles { counts[role, default: 0] += 1 }
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .first?
            .key
    }
}
