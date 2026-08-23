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
    /// Every file in the project, Swift or not, for rules that reason about
    /// shape rather than about code.
    public let allFiles: [String]
    public let scope: CheckScope

    public init(
        configuration: Configuration,
        graph: ProjectGraph,
        assignment: RoleAssignment,
        symbols: SymbolIndex,
        catalog: FrameworkCatalog,
        files: [AnalyzedFile],
        allFiles: [String] = [],
        scope: CheckScope
    ) {
        self.configuration = configuration
        self.graph = graph
        self.assignment = assignment
        self.symbols = symbols
        self.catalog = catalog
        self.files = files
        self.allFiles = allFiles
        self.scope = scope
    }

    /// Every package directory, longest first so that a nested package wins
    /// over the one containing it.
    ///
    /// A project with no packages at all yields a single empty entry meaning
    /// the repository itself. That is not a special case so much as the common
    /// one: most iOS apps are a single Xcode target, and rules that grouped by
    /// package would otherwise skip them entirely — exempting exactly the
    /// codebases with the least structure from the rules about structure.
    public var packageDirectories: [String] {
        let declared = Set(graph.orderedModules.compactMap(\.packageDirectory)).filter { !$0.isEmpty }
        guard !declared.isEmpty else { return [""] }
        return declared.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
    }

    /// The package a path belongs to, found by containment rather than through
    /// the module graph — a test target not yet declared in the manifest still
    /// lives inside a package, and a rule about missing tiers is precisely the
    /// one that has to see it.
    public func package(containing path: String) -> String? {
        packageDirectories.first { contains(path, in: $0) }
    }

    /// Whether a path lies inside a package. The empty package is the
    /// repository, and contains everything.
    public func contains(_ path: String, in package: String) -> Bool {
        package.isEmpty || path.hasPrefix(package + "/")
    }

    /// Where to report something that is true of a whole package: its manifest
    /// if it has one, otherwise the file that declared the rule it is breaking.
    public func anchor(for package: String) -> String {
        let manifest = Paths.join(package, "Package.swift")
        if allFiles.contains(manifest) { return manifest }
        return package.isEmpty ? ConfigurationLoader.fileName : package
    }

    /// A package's name for a report. The repository itself has none, so it is
    /// described rather than named.
    public func label(for package: String) -> String {
        package.isEmpty ? "This project" : "`\(Paths.lastComponent(of: package))`"
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

        guard definition.mayDepend(on: to) else { return .roleRefused }
        // The other layer also gets a say. `composition` may depend on anything,
        // which is exactly why something has to be able to refuse it.
        guard configuration.definition(for: to)?.isVisible(to: from) ?? true else { return .notVisible }
        return .permitted
    }
}

public enum DependencyVerdict: Sendable, Equatable {
    case permitted
    /// The target layer is not on this layer's list.
    case roleRefused
    /// Same layer, different package, and this layer keeps its siblings apart.
    case sameRoleRefused
    /// The target layer refuses to be depended on by this one.
    case notVisible
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
    /// The severity of one of this rule's identifiers before the project has
    /// its say. A rule that reports two different kinds of failure may hold
    /// them to two different standards, and anything listing the rules has to
    /// be able to ask rather than assume.
    func defaultSeverity(for identifier: String) -> Severity
    func evaluate(_ context: RuleContext) -> [Violation]
}

extension Rule {
    public var emittedIdentifiers: [String] { [identifier] }
    public var needsWholeProject: Bool { false }
    public func defaultSeverity(for identifier: String) -> Severity { defaultSeverity }
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
    public static let singleResponsibility =
        "Robert C. Martin, Clean Architecture (2017), Ch. 7 — The Single Responsibility Principle."
    public static let ubiquitousLanguage =
        "Eric Evans, Domain-Driven Design (2003), Ch. 2 — Ubiquitous Language; Ch. 5 — Services."
    public static let testBoundary =
        "Robert C. Martin, Clean Architecture (2017), Ch. 28 — The Test Boundary."
    public static let testDoubles =
        "Gerard Meszaros, xUnit Test Patterns (2007) — Test Double; Martin Fowler, Mocks Aren't Stubs (2007)."
    public static let testDataBuilder =
        "Freeman & Pryce, Growing Object-Oriented Software, Guided by Tests (2009), Ch. 22 — Constructing Complex Test Data."
    public static let acceptanceTests =
        "Robert C. Martin, The Clean Coder (2011), Ch. 7 — Acceptance Testing."
    public static let testSupport =
        "Gerard Meszaros, xUnit Test Patterns (2007) — Test Utility Method; Freeman & Pryce, GOOS (2009), Ch. 22."
    public static let compositionRoot =
        "Seemann & van Deursen, Dependency Injection: Principles, Practices, and Patterns (2019), Ch. 4 — Composition Root."
}
