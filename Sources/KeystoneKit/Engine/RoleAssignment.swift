import Foundation

/// Which role every file and every module belongs to.
///
/// Resolution runs in three passes because the two ways of stating a role
/// disagree usefully. A path pattern is a claim about this repository and wins
/// outright. A target pattern is a claim about a naming convention, and is
/// consulted next. What is left over inherits from the module that compiles it,
/// so a project can describe its architecture in whichever of the two languages
/// its layout actually speaks — and a file that fits neither is reported rather
/// than quietly assumed to be fine.
public struct RoleAssignment: Sendable {
    public let fileRoles: [String: Role]
    public let moduleRoles: [String: Role]
    public let unclassifiedFiles: [String]

    private let configuration: Configuration

    public init(configuration: Configuration, graph: ProjectGraph, swiftFiles: [String]) {
        self.configuration = configuration

        let pathClaims = configuration.orderedRoles.map { ($0.name, GlobSet($0.definition.paths)) }
        let targetClaims = configuration.orderedRoles.map { ($0.name, GlobSet($0.definition.targets)) }

        // Pass one: paths only.
        var fileRoles: [String: Role] = [:]
        for file in swiftFiles {
            if let role = RoleAssignment.mostSpecific(claims: pathClaims, subject: file) {
                fileRoles[file] = role
            }
        }

        // Pass two: a module's role, from its name if the configuration says
        // so, otherwise from what its files already turned out to be.
        var moduleRoles: [String: Role] = [:]
        var filesByModule: [String: [String]] = [:]
        for file in swiftFiles {
            guard let module = graph.module(owning: file) else { continue }
            filesByModule[module.name, default: []].append(file)
        }

        for module in graph.orderedModules {
            if let role = RoleAssignment.mostSpecific(claims: targetClaims, subject: module.name) {
                moduleRoles[module.name] = role
                continue
            }
            let roles = (filesByModule[module.name] ?? []).compactMap { fileRoles[$0] }
            if let modal = RoleAssignment.modal(roles) {
                moduleRoles[module.name] = modal
                continue
            }
            // A test bundle is a test bundle whatever it is called. This is the
            // one place the build system's own word is taken as evidence.
            if module.kind.isTest, configuration.roles[Role.tests.rawValue] != nil {
                moduleRoles[module.name] = .tests
            }
        }

        // Pass three: files the patterns missed inherit from their module.
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
    }

    public func role(ofFile path: String) -> Role? {
        fileRoles[path]
    }

    public func role(ofModule name: String) -> Role? {
        moduleRoles[name]
    }

    public func definition(ofFile path: String) -> RoleDefinition? {
        role(ofFile: path).flatMap { configuration.definition(for: $0) }
    }

    /// The claim with the most literal characters wins, so
    /// `Component/*/Sources/Domain/**` beats `Component/**` without either
    /// having to say which is more important.
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
    /// between two roles lands somewhere predictable rather than somewhere
    /// that depends on file-system ordering.
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
