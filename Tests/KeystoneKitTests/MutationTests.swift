import Foundation
import Testing
@testable import KeystoneKit

@Suite("A correct project passes")
struct CleanFixtureTests {
    @Test("the multi-package fixture has no violations at all")
    func multiPackageFixtureIsClean() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        let result = try fixture.check()
        #expect(result.violations.isEmpty, "\(result.violations.map(\.summary))")
    }

    @Test("the single-target fixture has no violations at all")
    func monolithFixtureIsClean() throws {
        let fixture = try Fixture.load("MonolithApp")
        defer { fixture.destroy() }

        let result = try fixture.check()
        #expect(result.violations.isEmpty, "\(result.violations.map(\.summary))")
    }
}

@Suite("Boundaries")
struct BoundaryMutationTests {
    @Test("a domain file importing SwiftUI is refused")
    func domainMayNotImportAUIFramework() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.prepend("Component/Catalog/Sources/Domain/Model/Item.swift", "import SwiftUI\n")

        #expect(try fixture.check().erroringRules.contains("framework-purity"))
    }

    @Test("a domain file importing its own data layer is refused")
    func domainMayNotImportData() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.prepend("Component/Catalog/Sources/Domain/Model/Item.swift", "import CatalogData\n")

        #expect(try fixture.check().erroringRules.contains("dependency-rule"))
    }

    @Test("a screen importing the data layer is refused")
    func presentationMayNotImportData() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.prepend("UI/CatalogUI/Sources/UI/CatalogViewModel.swift", "import CatalogData\n")

        #expect(try fixture.check().erroringRules.contains("dependency-rule"))
    }

    @Test("a domain file reaching URLSession through Foundation is refused")
    func domainMayNotUseRestrictedSymbols() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.append("Component/Catalog/Sources/Domain/Model/Item.swift", """

        import Foundation

        extension Item {
            static func fetch() -> URLSession { URLSession.shared }
        }
        """)

        #expect(try fixture.check().erroringRules.contains("restricted-symbols"))
    }

    @Test("a domain target given a data dependency in the manifest is refused")
    func manifestMayNotPointDomainAtData() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.replace(
            "Component/Catalog/Package.swift",
            "name: \"Catalog\",\n            path: \"Sources\",",
            with: "name: \"Catalog\",\n            dependencies: [\"CatalogData\"],\n            path: \"Sources\","
        )

        let rules = try fixture.check().erroringRules
        #expect(rules.contains("target-dependency-rule"))
        // The same edit closes a loop, since CatalogData already depends on
        // Catalog. Both rules should see it; they are describing different
        // consequences of one mistake.
        #expect(rules.contains("no-cycles"))
    }

    @Test("a domain target taking a third-party package is refused")
    func domainMayNotTakeAThirdPartyPackage() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.replace(
            "Component/Catalog/Package.swift",
            ".package(path: \"../../Library/Networking\")",
            with: ".package(path: \"../../Library/Networking\"),\n        .package(url: \"https://github.com/example/Alamofire.git\", from: \"5.0.0\")"
        )
        try fixture.replace(
            "Component/Catalog/Package.swift",
            "name: \"Catalog\",\n            path: \"Sources\",",
            with: "name: \"Catalog\",\n            dependencies: [.product(name: \"Alamofire\", package: \"Alamofire\")],\n            path: \"Sources\","
        )

        #expect(try fixture.check().erroringRules.contains("third-party-boundary"))
    }

    @Test("sibling features may be kept apart when a project asks for it")
    func featureIsolationIsAvailableButOptIn() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        // The preset allows screens to compose, because the reference project
        // does. Turning the stricter policy on must actually change the answer,
        // otherwise the setting is decoration.
        var configuration = try fixture.configuration()
        var presentation = configuration.roles["presentation"]!
        presentation.sameRole = .deny
        configuration.roles["presentation"] = presentation
        try ConfigurationLoader.write(configuration, to: Paths.join(fixture.root, ConfigurationLoader.fileName))

        try fixture.write("UI/OtherUI/Package.swift", """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "OtherUI",
            products: [.library(name: "OtherUI", targets: ["OtherUI"])],
            dependencies: [.package(path: "../CatalogUI")],
            targets: [
                .target(
                    name: "OtherUI",
                    dependencies: [.product(name: "CatalogUI", package: "CatalogUI")],
                    path: "Sources/UI"
                )
            ]
        )
        """)
        try fixture.write("UI/OtherUI/Sources/UI/OtherView.swift", """
        import CatalogUI
        import SwiftUI

        public struct OtherView: View {
            public init() {}
            public var body: some View { CatalogListView(model: .init(browseCatalog: fatalError())) }
        }
        """)

        #expect(try fixture.check().erroringRules.contains("feature-isolation"))
    }

    @Test("a boundary crossed inside one module, where no import can catch it, is still refused")
    func typeReferencesAreCheckedWhenThereAreNoModules() throws {
        let fixture = try Fixture.load("MonolithApp")
        defer { fixture.destroy() }

        try fixture.replace(
            "App/Presentation/OrderListViewModel.swift",
            "public init(repository: any OrderRepository) {\n        self.repository = repository\n    }",
            with: "public init() {\n        self.repository = DefaultOrderRepository()\n    }"
        )

        #expect(try fixture.check().erroringRules.contains("type-reference-boundary"))
    }

    @Test("a dependency the manifest declares and nothing imports is a warning")
    func declaredButUnusedDependenciesWarn() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.replace(
            "UI/CatalogUI/Package.swift",
            "name: \"CatalogUI\",\n            dependencies: [",
            with: "name: \"CatalogUI\",\n            dependencies: [\n                .product(name: \"Networking\", package: \"Networking\"),"
        )

        let result = try fixture.check()
        #expect(result.warningRules.contains("dependencies-are-used"))
        #expect(!result.erroringRules.contains("dependencies-are-used"))
    }

    @Test("a product vending several targets is judged as one manifest entry")
    func aProductIsNotJudgedTargetByTarget() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        // `CatalogUIDI` depends on the `CatalogDI` product and imports one of
        // the targets that product vends. Reading the resolved edges rather
        // than the manifest entry called every other target in the product
        // unused, which put fifty-one findings on a project whose manifests
        // have no line to delete for any of them.
        #expect(try fixture.check().violations.allSatisfy { $0.rule != "dependencies-are-used" })
    }

    @Test("importing a module the manifest does not declare is a warning, not a refusal")
    func undeclaredImportsWarn() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.prepend("UI/CatalogUI/Sources/UI/CatalogViewModel.swift", "import Networking\n")

        let result = try fixture.check()
        #expect(result.warningRules.contains("imports-are-declared"))
        #expect(!result.erroringRules.contains("imports-are-declared"))
    }
}

@Suite("Freeze")
struct FreezeTests {
    /// The whole contract in one test: what exists today stops being reported,
    /// and the next edge is refused.
    @Test("freezing accepts today's edges and refuses the next one")
    func freezeAcceptsTodayAndRefusesTomorrow() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        // A screen reaching storage. Refused by the preset.
        try fixture.prepend("UI/CatalogUI/Sources/UI/CatalogViewModel.swift", "import CatalogData\n")
        #expect(try fixture.check().erroringRules.contains("dependency-rule"))

        #expect(Commands.freeze(Arguments(["freeze", "--root", fixture.root])) == ExitCode.clean)

        // Now permitted, because the project froze its own shape.
        #expect(!(try fixture.check().erroringRules.contains("dependency-rule")))

        // And the manifest says out loud that this was debt rather than a
        // decision, so nobody reads the allow-list as an endorsement.
        let configuration = try fixture.configuration()
        let reason = configuration.roles["presentation"]?.reason ?? ""
        #expect(reason.contains("Frozen"))

        // A different edge, which did not exist when freeze ran, is still
        // refused. Without this the command is just a slower baseline.
        try fixture.prepend("UI/CatalogUI/Sources/UI/CatalogListView.swift", "import Networking\n")
        #expect(try fixture.check().erroringRules.contains("dependency-rule"))
    }

    @Test("freezing a clean project narrows it rather than widening it")
    func freezeTightensACleanProject() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        #expect(Commands.freeze(Arguments(["freeze", "--root", fixture.root])) == ExitCode.clean)

        // Nothing was widened, so no role carries a frozen reason.
        let configuration = try fixture.configuration()
        for (_, definition) in configuration.roles {
            #expect(!(definition.reason ?? "").contains("Frozen"))
        }
        #expect(try fixture.check().violations.isEmpty)
    }

    @Test("a layer with no modules is left alone rather than frozen to nothing")
    func emptyLayersAreNotFrozen() throws {
        let fixture = try Fixture.load("MonolithApp")
        defer { fixture.destroy() }

        #expect(Commands.freeze(Arguments(["freeze", "--root", fixture.root])) == ExitCode.clean)
        #expect(try fixture.check().violations.isEmpty)
    }
}

@Suite("Placement")
struct PlacementMutationTests {
    @Test("a view model in the domain is refused")
    func viewModelsMayNotLiveInTheDomain() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.write("Component/Catalog/Sources/Domain/Model/ItemViewModel.swift", """
        public final class ItemViewModel {
            public init() {}
        }
        """)

        #expect(try fixture.check().erroringRules.contains("declaration-placement"))
    }

    @Test("a repository contract in the data layer is refused")
    func repositoryContractsMayNotLiveInData() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.write("Component/Catalog/Sources/Data/StockRepository.swift", """
        public protocol StockRepository: Sendable {
            func level() async -> Int
        }
        """)

        #expect(try fixture.check().erroringRules.contains("declaration-placement"))
    }

    @Test("a DTO outside the data layer is refused")
    func dtosMayNotEscapeData() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.write("Component/Catalog/Sources/Domain/Model/StockDTO.swift", """
        public struct StockDTO: Sendable {
            public let level: Int
        }
        """)

        #expect(try fixture.check().erroringRules.contains("declaration-placement"))
    }

    @Test("a screen extending a domain type is refused")
    func presentationMayNotExtendDomainTypes() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.append("UI/CatalogUI/Sources/UI/CatalogViewModel.swift", """

        extension Item {
            var displayName: String { name.uppercased() }
        }
        """)

        #expect(try fixture.check().erroringRules.contains("extension-boundary"))
    }

    @Test("a repository protocol declared where it belongs is left alone")
    func contractsInTheDomainArePermitted() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.write("Component/Catalog/Sources/Domain/Repository/StockRepository.swift", """
        public protocol StockRepository: Sendable {
            func level() async -> Int
        }
        """)

        #expect(try fixture.check().violations.isEmpty)
    }
}

@Suite("Hygiene")
struct HygieneMutationTests {
    @Test("a type named as an implementation that implements nothing is a warning")
    func implementationsShouldHaveAContract() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.write("Component/Catalog/Sources/Data/DefaultStockGauge.swift", """
        public struct DefaultStockGauge {
            public init() {}
        }
        """)

        #expect(try fixture.check().warningRules.contains("contract-before-implementation"))
    }

    @Test("a shared instance outside the composition root is a warning")
    func sharedInstancesAreWarnedAbout() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.append("Component/Catalog/Sources/Data/DefaultItemRepository.swift", """

        public enum Registry {
            public static let shared = 1
        }
        """)

        #expect(try fixture.check().warningRules.contains("no-shared-singletons"))
    }

}
