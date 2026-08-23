import Foundation

/// The architecture this tool moves a codebase toward.
///
/// The layer *properties* are fixed — what a domain may reach, which frameworks
/// a screen refuses — because those are the architecture. The layer *paths* are
/// not, because those are the project. Inference fills the paths in; everything
/// here is true of a clean architecture whatever the directories are called.
public enum Presets {
    public static func cleanArchitecture(paths: [Role: [String]]) -> Configuration {
        var roles: [String: RoleDefinition] = [:]

        roles[Role.domain.rawValue] = RoleDefinition(
            description: "Entities, use cases and the contracts they are satisfied through. The stable centre.",
            paths: paths[.domain] ?? [],
            mayDependOn: [],
            sameRole: .allow,
            deniedFrameworks: [
                FrameworkCatalog.ui, FrameworkCatalog.persistence, FrameworkCatalog.networking,
                FrameworkCatalog.crypto, FrameworkCatalog.media, FrameworkCatalog.system
            ],
            allowsThirdParty: false,
            deniedSymbols: [
                "URLSession", "URLRequest", "URLComponents", "FileManager", "UserDefaults",
                "NSManagedObject", "NSPersistentContainer", "NotificationCenter", "Bundle"
            ],
            // Words that belong to the layer that owns the wire. A domain
            // service is named for what the business needs done, not for the
            // thing on the other end of it.
            deniedNameSuffixes: [
                "Client", "API", "Endpoint", "Gateway", "DAO", "Database",
                "Cache", "Socket", "Serializer", "Codec"
            ],
            reason: "The domain states the business rules and declares what it needs as protocols. "
                + "Anything that talks to a network, a disk, a framework or a screen is a detail: put the "
                + "protocol here and the implementation in the layer that owns that detail, then let the "
                + "composition root introduce them. Source code dependencies point inward, never out."
        )

        roles[Role.data.rawValue] = RoleDefinition(
            description: "Implementations of the domain's contracts: repositories, clients, stores, DTOs.",
            paths: paths[.data] ?? [],
            mayDependOn: [Role.domain.rawValue, Role.library.rawValue],
            sameRole: .denyAcrossPackages,
            deniedFrameworks: [FrameworkCatalog.ui],
            allowsThirdParty: true,
            reason: "The data layer answers to the domain and to nothing above it. If it needs something a "
                + "screen has, the dependency is inverted — pass it in from the composition root instead."
        )

        roles[Role.presentation.rawValue] = RoleDefinition(
            description: "Views and view models. Views are passive; view models delegate to use cases.",
            paths: paths[.presentation] ?? [],
            mayDependOn: [Role.domain.rawValue, Role.library.rawValue],
            // Screens compose. A home screen showing a product card, or a
            // checkout button raising a sign-in sheet, is reuse rather than
            // coupling, and forbidding it by default would fire on correct
            // code. Set this to `denyAcrossPackages` if you want features kept
            // strictly apart, meeting only at the composition root.
            sameRole: .allow,
            deniedFrameworks: [
                FrameworkCatalog.persistence, FrameworkCatalog.networking, FrameworkCatalog.crypto
            ],
            allowsThirdParty: true,
            deniedSymbols: ["URLSession", "URLRequest", "FileManager", "UserDefaults", "NSManagedObject"],
            reason: "A screen reaches the domain and never storage. Take the use case protocol through the "
                + "initialiser and let the composition root decide which concrete type satisfies it — that is "
                + "what makes the screen testable without a network or a database."
        )

        roles[Role.composition.rawValue] = RoleDefinition(
            description: "The one place that knows every concrete type. Wiring, and nothing else.",
            paths: paths[.composition] ?? [],
            mayDependOn: ["*"],
            sameRole: .allow,
            allowsThirdParty: true,
            reason: "Composition is allowed to know about everything, which is precisely why nothing else has "
                + "to. Keep behaviour out of it: if this code does something other than choosing and connecting "
                + "implementations, it belongs in a layer."
        )

        roles[Role.library.rawValue] = RoleDefinition(
            description: "Domain-free utilities. A library knows nothing about the app that links it.",
            paths: paths[.library] ?? [],
            mayDependOn: [Role.library.rawValue],
            sameRole: .allow,
            deniedFrameworks: [FrameworkCatalog.ui],
            allowsThirdParty: true,
            reason: "A library must stay ignorant of the app linking it. If it needs a domain type it is not a "
                + "library — move it into the component that owns that concept."
        )

        roles[Role.testSupport.rawValue] = RoleDefinition(
            description: "Doubles, drivers and builders shared between test targets.",
            paths: paths[.testSupport] ?? [],
            // Anything, because a double has to see whatever it stands in for —
            // a screen's stub needs the screen's protocols. The constraint that
            // matters here runs the other way: who may see *this*.
            mayDependOn: ["*"],
            // The point of the role. SwiftPM cannot share a test target across
            // packages, so shared test code has to be an ordinary module — and
            // an ordinary module can be linked by anything, including the app.
            // Stating who may see it is what keeps test doubles out of the
            // shipping binary.
            visibleTo: [Role.tests.rawValue, Role.testSupport.rawValue],
            sameRole: .allow,
            allowsThirdParty: true,
            reason: "This module exists to serve test targets and is not built to ship. It stands in for "
                + "real behaviour, so anything depending on it outside a test is depending on a pretence. "
                + "If production needs what is in here, it is not test support — move it into the layer "
                + "that owns it."
        )

        roles[Role.tests.rawValue] = RoleDefinition(
            description: "Test targets. Free to reach anywhere, since a test's job is to hold the rest to account.",
            paths: paths[.tests] ?? [],
            mayDependOn: ["*"],
            sameRole: .allow,
            allowsThirdParty: true
        )

        return Configuration(
            version: 1,
            roles: roles,
            conventions: conventions,
            extensionBoundaries: [
                ExtensionBoundary(
                    from: [.presentation],
                    declaredIn: [.domain],
                    reason: "A screen may not add members to a domain type. The member then exists in the module "
                        + "that added it and silently does not in the one next door, which grows its own copy of "
                        + "the same rule. Build a presentation model instead: a struct this screen owns, holding "
                        + "already-worded values, mapped from the domain type by an initialiser in its own body."
                )
            ],
            tests: testing
        )
    }

    /// Two tiers that answer different questions, and a third for the one thing
    /// neither can answer.
    ///
    /// An acceptance failure says *this stopped working*; a unit failure says
    /// *which rule is wrong*. Neither can tell you a screen now lays something out
    /// wrongly, which is what the snapshot tier is for — and
    /// why it is required of a package with views rather than of everything.
    public static let testing = TestsConfiguration(
        tiers: [
            TestTier(
                name: "acceptance",
                paths: ["**/Tests/*AcceptanceTests/**"],
                namesReadAsProse: true,
                mayNotReference: [.data],
                requiredFor: [
                    TierRequirement(
                        roles: [.domain],
                        reason: "Every component states its business rules as a journey somebody takes, "
                            + "readable by a person who does not know the code."
                    )
                ],
                reason: "Drive the feature through this tier's own driver — the role objects in Support/ — "
                    + "so the feature can be rearranged underneath the suite without touching it. The "
                    + "driver may name concrete types; the tests may not."
            ),
            TestTier(
                name: "unit",
                paths: ["**/Tests/*UnitTests/**"],
                requiredFor: [
                    TierRequirement(roles: [.domain]),
                    TierRequirement(
                        roles: [.presentation],
                        declaring: ConventionMatch(nameSuffix: "ViewModel", kinds: [.struct, .class, .actor]),
                        reason: "A feature package earns a unit tier by having a view model. One with "
                            + "nothing but views has no unit for a unit test to name."
                    )
                ]
            ),
            TestTier(
                name: "snapshot",
                paths: ["**/Tests/*SnapshotTests/**"],
                requiredFor: [
                    TierRequirement(
                        roles: [.presentation],
                        declaring: ConventionMatch(nameSuffix: "View", kinds: [.struct]),
                        reason: "A view is the one thing neither other tier can check. Apple ships no "
                            + "snapshot testing, so this means pointfreeco/swift-snapshot-testing, which "
                            + "has native Swift Testing support."
                    )
                ],
                artifactDirectory: "__Snapshots__"
            )
        ],
        // Empty, so the shape rule is inert unless a project asks for it.
        //
        // The pyramid is about cost and scope — how much of the system a test
        // exercises, how slow it is, how often it breaks for reasons unrelated
        // to the change. This can only count files in directories, and counting
        // is a proxy that holds solely when the tiers actually differ in cost.
        //
        // Here they do not. An acceptance suite driven through a testing API
        // against in-memory fakes never touches a network or a database: it is
        // a mid-pyramid service test phrased in the business's language, which
        // is Vocke's point in *The Practical Test Pyramid* that acceptance
        // testing is a purpose rather than a level. Counting it against the
        // unit tier measured nothing, and said so loudly — on the reference
        // project the classic order flagged six packages and the reverse order
        // flagged ten, which is what a rule looks like when it is reading the
        // wrong signal.
        //
        // A project whose tiers genuinely differ in cost — one that drives a
        // simulator or a real service — states the order and gets the rule.
        pyramid: []
    )

    /// Conventions worth having in nearly every Swift codebase, because they
    /// are the names Swift developers already reach for. Each one is a pairing
    /// of a suffix with a layer; the pairing is the rule, not the suffix.
    public static let conventions: [Convention] = [
        Convention(
            name: "use-cases-live-in-domain",
            match: ConventionMatch(nameSuffix: "UseCase", kinds: [.protocol, .struct, .class, .actor, .enum]),
            requireRole: [.domain],
            exemptRoles: [.tests, .composition],
            reason: "A use case is application-specific business logic, so it belongs beside the rules it "
                + "coordinates rather than beside the screen that happens to call it first.",
            source: Sources.businessRules
        ),
        Convention(
            name: "repository-contracts-live-in-domain",
            match: ConventionMatch(nameSuffix: "Repository", kinds: [.protocol]),
            requireRole: [.domain],
            reason: "The contract belongs to the layer that needs it satisfied; only the implementation belongs "
                + "to the layer that satisfies it. That split is what points the dependency inward.",
            source: Sources.separatedInterface
        ),
        Convention(
            name: "repository-implementations-live-in-data",
            match: ConventionMatch(nameSuffix: "Repository", kinds: [.struct, .class, .actor]),
            requireRole: [.data],
            exemptRoles: [.tests, .composition],
            reason: "A concrete repository is infrastructure. Put it in the data layer and let the composition "
                + "root hand it to the domain as the protocol.",
            source: Sources.repository
        ),
        Convention(
            name: "dtos-live-in-data",
            match: ConventionMatch(nameSuffix: "DTO", kinds: [.struct, .class, .enum]),
            requireRole: [.data],
            reason: "A DTO is a wire format, not a business concept. It must not escape the data layer — map it "
                + "to a domain type at the boundary and let the shape of the payload stop there.",
            source: Sources.dataTransferObject
        ),
        Convention(
            name: "view-models-live-in-presentation",
            match: ConventionMatch(nameSuffix: "ViewModel", kinds: [.struct, .class, .actor]),
            requireRole: [.presentation],
            exemptRoles: [.tests, .composition],
            reason: "A view model is presentation. One living anywhere else means business logic has followed "
                + "it there.",
            source: Sources.humbleObject
        ),
        Convention(
            name: "views-live-in-presentation",
            match: ConventionMatch(nameSuffix: "View", kinds: [.struct]),
            requireRole: [.presentation],
            // The composition root owns the app shell — a root view and the
            // model behind it are part of assembling the app, not a layer
            // drawing its own screen.
            exemptRoles: [.tests, .composition],
            reason: "A view is presentation, and a view declared outside it is a layer drawing its own screen.",
            source: Sources.humbleObject
        )
        // `clients-live-in-data` and `stores-live-in-data` are deliberately
        // absent. Both read well until you meet the app they are wrong for: a
        // CRM whose `Client` is its most important entity, a retail app whose
        // `Store` is a place on a map. `UseCase`, `Repository`, `DTO`,
        // `ViewModel` and `View` name patterns, so they can be defaults; a
        // suffix that is also an ordinary noun cannot. Both are in the README
        // as opt-in conventions, for the projects they suit.
    ]
}
