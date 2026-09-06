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
    /// Files whose only evidence is what kind of target holds them.
    ///
    /// An app target is composition at its entry points, but a file five
    /// directories inside one, in a folder the vocabulary does not recognise,
    /// has told us nothing about itself. The role is a reasonable default for
    /// the target and no statement at all about the file, and a rule that
    /// compares two layers must know the difference.
    public let placedByTargetKind: Set<String>
    /// Files placed by what they are made of rather than by what they are called.
    public let placedByContents: Set<String>
    public let moduleRoles: [String: Role]
    public let unclassifiedFiles: [String]
    /// How each module was placed, for reports that must show their working.
    public let evidence: [String: String]

    private let configuration: Configuration

    /// `facts` is what has been parsed. It may be empty, or hold one file: the
    /// pre-write hook parses only the file being written, so it places that file
    /// from its own contents and reads every other module from names alone. The
    /// hook is therefore the more cautious of the two — it places less, so it
    /// judges less, and a check that cannot decide permits the write. CI, which
    /// has parsed everything, is the authority.
    public init(
        configuration: Configuration,
        graph: ProjectGraph,
        swiftFiles: [String],
        facts: [String: SourceFacts] = [:]
    ) {
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

        // A path that says "test" comes before anything a file contains. A test
        // may be built out of whatever it is testing, so a driver holding a
        // fake store says what the double is made of, not which layer it is in.
        // The reference project's `Shopper`, `Buyer` and `Waiter` are exactly
        // that, and reading their contents first put them in `data` and
        // invented twenty-five boundary violations.
        for file in swiftFiles where fileRoles[file] == nil {
            guard let match = LayerVocabulary.testMatch(forDirectory: Paths.directory(of: file)),
                  known.contains(match.role.rawValue) else { continue }
            fileRoles[file] = match.role
        }

        var filesByModule: [String: [String]] = [:]
        for file in swiftFiles {
            guard let module = graph.module(owning: file) else { continue }
            filesByModule[module.name, default: []].append(file)
        }

        // Then what the build system says the target is. A manifest declaring a
        // `.testTarget`, or an Xcode target of kind app, is a fact the project
        // states about itself; a folder whose name merely ends in `UI` is a
        // guess about one path segment. The fact goes first. It did not, and an
        // app called `ModularSwiftUI` had its own `AppDelegate` filed under
        // presentation.
        // An app target is the composition root only where there is something
        // to compose. Composition is the layer that introduces modules to each
        // other; a project built as one target has no modules to introduce, so
        // calling its app target composition does not describe it — it exempts
        // it. UTM is one target of 221 files, every rule about layers was
        // switched off for all of them, and `status` reported "100% of Swift
        // files are inside the architecture" about a project this tool had
        // learned nothing whatever about. Where there is only one production
        // module, its files speak for themselves and what cannot speak is said
        // to be unclassified, which is the true answer.
        //
        // The test is where the code is, not what the targets are called.
        // "Another production target exists" made UTM a composition root on the
        // strength of a one-file command-line tool, next to an app target
        // holding the other two hundred and twenty files. So: most of the
        // project's Swift must live outside the app for the app to be wiring
        // it. The reference project keeps fifteen files in its app target and
        // three hundred and ninety-three in packages, which is what a
        // composition root looks like; UTM keeps everything in one place, which
        // is a project whose layers this tool has to read from the files.
        //
        // Majority is the same measure `modal` uses below. A tool that reads
        // evidence needs one idea of what "most" means, not two.
        let appFiles = graph.orderedModules
            .filter { $0.kind == .app }
            .reduce(into: 0) { $0 += (filesByModule[$1.name] ?? []).count }
        let productionFiles = graph.orderedModules
            .filter { !$0.kind.isTest }
            .reduce(into: 0) { $0 += (filesByModule[$1.name] ?? []).count }
        let composesModules = productionFiles > 0 && appFiles * 2 <= productionFiles

        var placedByTargetKind: Set<String> = []
        for file in swiftFiles where fileRoles[file] == nil {
            guard let module = graph.module(owning: file) else { continue }
            if module.kind.isTest, known.contains(Role.tests.rawValue) {
                fileRoles[file] = .tests
                placedByTargetKind.insert(file)
            } else if module.kind == .app, composesModules, known.contains(Role.composition.rawValue) {
                fileRoles[file] = .composition
                placedByTargetKind.insert(file)
            }
        }

        // Then what the file itself is made of. A type conforming to `View`, an
        // `@main`, an `NSManagedObject`, a `URLSession` — these are the
        // platform's own vocabulary, and a file that adopts them has said which
        // layer's machinery it is built on. It sits below the build system,
        // which states a fact about a whole target, and above a name suffix,
        // which is the weakest reading there is.
        //
        // It can never yield `domain` or `library`: those have no marker, being
        // what is left when a file touches no screen, no store and no wire.
        var placedByContents: Set<String> = []
        for file in swiftFiles where fileRoles[file] == nil {
            guard let facts = facts[file],
                  let role = ContentMarkers.declaredRole(of: facts),
                  known.contains(role.rawValue) else { continue }
            fileRoles[file] = role
            placedByContents.insert(file)
        }

        // Then what the directories call themselves, in as many words.
        //
        // Below contents, not above. Run over thirty-two open-source apps, a
        // directory name lost to the file it named in every one of them.
        // `WordPressIntelligence/UseCases/TranslationViewModel.swift` declares
        // `ObservableObject` and a `: View` and collected seven findings as
        // `domain` — two of them from `declaration-placement`, which is the tool
        // diagnosing its own misplacement and telling the author to move a file
        // that never moved. A folder called `Utilities` made a `ViewModifier` a
        // library; `Entity` made an `NSManagedObject` the domain; `Library` made
        // firefox's bookmarks panel a utility package.
        //
        // A name is what somebody meant. A conformance is what they wrote, the
        // compiler checks it, and it cannot go stale. Contents can never yield
        // `domain` or `library`, so a directory called `Domain/` is still what
        // places a domain file; this rung only loses where a fact refutes it.
        for file in swiftFiles where fileRoles[file] == nil {
            guard let match = LayerVocabulary.exactMatch(forDirectory: Paths.directory(of: file)),
                  known.contains(match.role.rawValue) else { continue }
            fileRoles[file] = match.role
        }

        // Only then the weakest reading of a name.
        for file in swiftFiles where fileRoles[file] == nil {
            guard let match = LayerVocabulary.suffixMatch(forDirectory: Paths.directory(of: file)),
                  known.contains(match.role.rawValue) else { continue }
            fileRoles[file] = match.role
        }

        // Last, before giving up on the file: what it merely touches. An
        // `import CoreData`, a `URLSession` — real evidence, but not the same
        // evidence as a conformance, so it is asked after every name in the
        // path has been asked and none of them answered.
        //
        // This rung is why the two readings are separate. Reading usage as
        // strongly as declaration re-labelled a `Domain/` file naming
        // `URLSession` as `data`, and deleting `restricted-symbols` by agreeing
        // with the mistake is the worst thing a checker can do. Refusing to
        // read usage at all left 717 files across the sample with no layer, and
        // an unclassified file gets no rule at all — quieter, and worse.
        for file in swiftFiles where fileRoles[file] == nil {
            guard let facts = facts[file],
                  let role = ContentMarkers.usedRole(of: facts),
                  known.contains(role.rawValue) else { continue }
            fileRoles[file] = role
            placedByContents.insert(file)
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
            if module.kind == .app, composesModules, known.contains(Role.composition.rawValue) {
                moduleRoles[module.name] = .composition
                evidence[module.name] = "application target"
                continue
            }
            // Every source root must agree. Reading only the first one in
            // array order placed home-assistant's 600-file `Shared-iOS` in
            // composition on the word `App`, from `Sources/App/Onboarding` —
            // the first of twenty-seven roots, twenty-six of which were never
            // looked at, including `Sources/Shared/Domain`. It also split this
            // repository's own reference project, where three `*DI` modules
            // read as presentation and nineteen as composition purely on which
            // root happened to come first. A module whose roots disagree is a
            // module spanning layers, and the honest answer is to say nothing
            // and let its files speak for themselves.
            let roots = module.sourceRoots.compactMap(LayerVocabulary.match(forDirectory:))
                .filter { known.contains($0.role.rawValue) }
            let agreed = Set(roots.map(\.role))
            if agreed.count == 1, let match = roots.first {
                moduleRoles[module.name] = match.role
                // Exact and suffix readings were reported with the same
                // sentence, so a reader could not tell the strongest name
                // evidence from the weakest.
                let exact = LayerVocabulary.exactMatch(forDirectory: module.sourceRoots.first ?? "") != nil
                evidence[module.name] = exact
                    ? "directory named `\(match.segment)`"
                    : "a directory called `\(match.segment)`, read for its ending"
                continue
            }

            // The modal must be a majority of the module's FILES, not of the
            // few that happened to hold a role. One file of fifty-four placed
            // IceCubesApp's entity package in composition, and one of a hundred
            // and nineteen placed duckduckgo's `Core` in tests — under an
            // evidence string that read "most of its files are". It was not
            // true, and it is now checked.
            let files = filesByModule[module.name] ?? []
            if let modal = RoleAssignment.modal(files.compactMap { fileRoles[$0] },
                                                outOf: files.count) {
                moduleRoles[module.name] = modal
                evidence[module.name] = "most of its files are `\(modal)`"
            }
        }

        // What is left is placed by what it depends on. A module that reaches
        // both a domain and a data module is wiring them together, whatever it
        // is called.
        // Read from a snapshot. This loop used to mutate the dictionary it was
        // reading, in alphabetical order, so one guess became the evidence for
        // the next: WordPress's `BuildSettingsKit` became domain because
        // nothing depended on it, and then `DesignSystem` — SwiftUI, full of
        // `: View` — became data because it depended on a domain module.
        let placed = moduleRoles
        var derived: [String: (Role, String)] = [:]
        for module in graph.orderedModules where placed[module.name] == nil {
            // A target holding no Swift at all is not asked. Everything above
            // failed to place it because there was nothing to read, and the
            // shape of its edges is the one piece of evidence still available —
            // which is exactly the evidence that says least. WordPress has
            // Objective-C targets whose names end in `UI`; a layer guessed for
            // one of them became the far side of 142 boundary findings against
            // Swift files this tool never read a line of. A module with no
            // Swift is a module this tool has no opinion about.
            guard !(filesByModule[module.name] ?? []).isEmpty else { continue }
            let edges = graph.edges[module.name] ?? []
            let reached = Set(edges.compactMap { placed[$0] })
            // A module that pulls in somebody else's package is not the stable
            // centre of anything; the domain refuses third-party dependencies
            // outright. Twenty of the seventy-six modules called "a candidate
            // for the stable centre" declare one, so the tool was reading a
            // layer off an absence it would then punish them for.
            let isLeaf = edges.isEmpty && (graph.externalEdges[module.name] ?? []).isEmpty
            guard let (role, why) = RoleAssignment.fromShape(reached, isLeaf: isLeaf),
                  known.contains(role.rawValue) else { continue }
            derived[module.name] = (role, why)
        }
        for (name, placement) in derived {
            moduleRoles[name] = placement.0
            evidence[name] = placement.1
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
        self.placedByTargetKind = placedByTargetKind
        self.placedByContents = placedByContents
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
        // "Depends on a presentation module" used to return composition, and
        // it is the app target that this describes — which is placed by its
        // kind long before the shape is consulted. What was left reaching a
        // presentation module was, overwhelmingly, another presentation
        // module: a feature on a design system. Calling those composition put
        // roughly seventy WordPress findings on modules that were screens.
        if reached.contains(.domain) {
            return (.data, "depends on a domain module without being a screen")
        }
        // A module that depends on nothing is not thereby the stable centre.
        // Measured across thirty-two apps, this arm placed seventy-six modules,
        // and the ones it named included an API client, a UserDefaults wrapper,
        // a GRDB persistence layer, a date-formatting library and a SwiftUI
        // style guide. Depending on nothing is a fact about a module's edges
        // and says nothing whatever about its layer.
        //
        // The final arm said so in its own evidence string — "no clear
        // evidence" — and then returned `domain` anyway, which is the strictest
        // layer in the preset: it refuses third-party packages, every UI,
        // persistence and networking framework, and URLSession. So the least
        // supported placement in the tool was also the one held to the highest
        // standard, and it produced errors at scale about modules that were
        // never the domain.
        //
        // Both are gone. A module the shape cannot place is left unplaced, and
        // its files are reported once as unclassified rather than judged
        // against a layer nobody established.
        return nil
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
    /// The role held by most of a module's files, or nothing.
    ///
    /// `outOf` is every file the module owns, including those holding no role
    /// at all. A role held by one file in fifty-four is not what most of them
    /// are, and saying so was how a package of entities became the composition
    /// layer.
    ///
    /// A tie decides nothing. It used to break by `Role.conventionalOrder`,
    /// which put `domain` first, so an evenly split module silently became the
    /// stable centre.
    static func modal(_ roles: [Role], outOf total: Int) -> Role? {
        guard !roles.isEmpty, total > 0 else { return nil }
        var counts: [Role: Int] = [:]
        for role in roles { counts[role, default: 0] += 1 }
        let ranked = counts.sorted { $0.value > $1.value }
        guard let winner = ranked.first else { return nil }
        if ranked.count > 1, ranked[1].value == winner.value { return nil }
        guard winner.value * 2 > total else { return nil }
        return winner.key
    }
}
