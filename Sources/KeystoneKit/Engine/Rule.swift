import Foundation

/// One Swift file, everything known about it.
public struct AnalyzedFile: Sendable {
    public var path: String
    public var role: Role?
    public var module: Module?
    public var facts: SourceFacts

    public init(path: String, role: Role?, module: Module?, facts: SourceFacts) {
        self.path = path
        self.role = role
        self.module = module
        self.facts = facts
    }
}

/// Whether the checker is looking at the whole repository or at one file that
/// has not been written yet.
///
/// The distinction is load-bearing. Some questions — is this import allowed —
/// are answerable from one file. Others — is there a cycle, is any file
/// unclassified — are facts about the set, and asking them of a single file
/// produces a confident wrong answer. A rule that cannot answer says so and is
/// skipped, rather than guessing while an agent waits.
public enum CheckScope: Sendable {
    case project
    case singleFile
}

public struct RuleContext: Sendable {
    public let configuration: Configuration
    public let graph: ProjectGraph
    public let assignment: RoleAssignment
    public let symbols: SymbolIndex
    public let catalog: FrameworkCatalog
    /// The files to report on. In project scope this is everything; in single
    /// file scope it is the one pending write.
    public let files: [AnalyzedFile]
    public let scope: CheckScope

    public init(
        configuration: Configuration,
        graph: ProjectGraph,
        assignment: RoleAssignment,
        symbols: SymbolIndex,
        catalog: FrameworkCatalog,
        files: [AnalyzedFile],
        scope: CheckScope
    ) {
        self.configuration = configuration
        self.graph = graph
        self.assignment = assignment
        self.symbols = symbols
        self.catalog = catalog
        self.files = files
        self.scope = scope
    }

    public func definition(for role: Role?) -> RoleDefinition? {
        role.flatMap { configuration.definition(for: $0) }
    }

    /// Whether a module of `from` may depend on a module of `to`, accounting
    /// for the same-role policy and for whether the two live in one package.
    public func permits(
        from: Role,
        to: Role,
        fromPackage: String?,
        toPackage: String?
    ) -> DependencyVerdict {
        guard let definition = configuration.definition(for: from) else { return .permitted }

        if from == to {
            switch definition.sameRole {
            case .allow:
                return .permitted
            case .deny:
                return .sameRoleRefused
            case .denyAcrossPackages:
                let same = fromPackage != nil && fromPackage == toPackage
                return same ? .permitted : .sameRoleRefused
            }
        }

        return definition.mayDepend(on: to) ? .permitted : .roleRefused
    }
}

public enum DependencyVerdict: Sendable, Equatable {
    case permitted
    /// The target layer is not on this layer's list.
    case roleRefused
    /// Same layer, different package, and this layer keeps its siblings apart.
    case sameRoleRefused
}

public protocol Rule: Sendable {
    /// The name used to disable the rule or change its severity.
    var identifier: String { get }
    /// Every identifier this rule can attach to a violation. A rule that
    /// distinguishes two kinds of failure reports them under two names, so a
    /// project can silence one without losing the other.
    var emittedIdentifiers: [String] { get }
    var defaultSeverity: Severity { get }
    /// True when the rule needs to see every file to be right.
    var needsWholeProject: Bool { get }
    func evaluate(_ context: RuleContext) -> [Violation]
}

extension Rule {
    public var emittedIdentifiers: [String] { [identifier] }
    public var needsWholeProject: Bool { false }
}

/// Short attributions, printed with the violation so a reader can go and
/// disagree with the source rather than with the tool.
public enum Sources {
    public static let dependencyRule =
        "Robert C. Martin, Clean Architecture (2017), Ch. 22 — The Clean Architecture."
    public static let acyclicDependencies =
        "Robert C. Martin, Clean Architecture (2017), Ch. 14 — Component Coupling, the Acyclic Dependencies Principle."
    public static let componentCohesion =
        "Robert C. Martin, Clean Architecture (2017), Ch. 13 — Component Cohesion."
    public static let humbleObject =
        "Robert C. Martin, Clean Architecture (2017), Ch. 23 — Presenters and Humble Objects."
    public static let businessRules =
        "Robert C. Martin, Clean Architecture (2017), Ch. 20 — Business Rules."
    public static let repository =
        "Martin Fowler, Patterns of Enterprise Application Architecture (2002), Ch. 13 — Repository."
    public static let dataTransferObject =
        "Martin Fowler, Patterns of Enterprise Application Architecture (2002), Ch. 15 — Data Transfer Object."
    public static let separatedInterface =
        "Martin Fowler, Patterns of Enterprise Application Architecture (2002), Ch. 18 — Separated Interface."
    public static let compositionRoot =
        "Seemann & van Deursen, Dependency Injection: Principles, Practices, and Patterns (2019), Ch. 4 — Composition Root."
}
