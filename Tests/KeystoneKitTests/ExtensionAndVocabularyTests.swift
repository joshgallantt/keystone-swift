import Foundation
import Testing
@testable import KeystoneKit

@Suite("Extensions")
struct ExtensionPolicyTests {
    /// The rule permits the two things only an extension can do, and one thing
    /// the language leaves no alternative to. Everything else scatters a type's
    /// surface across files, which is the objection.
    func check(_ body: String, at path: String = "Component/Catalog/Sources/Domain/Model/Extras.swift") throws -> CheckResult {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }
        try fixture.write(path, body)
        return try fixture.check()
    }

    @Test("an extension that only adds members is refused")
    func bareExtensionsAreRefused() throws {
        let result = try check("""
        extension Item {
            var shouty: String { name.uppercased() }
        }
        """)
        #expect(result.erroringRules.contains("no-extensions"))
    }

    @Test("an extension that declares a conformance is the point of extensions")
    func conformancesArePermitted() throws {
        let result = try check("""
        extension Item: CustomStringConvertible {
            public var description: String { name }
        }
        """)
        #expect(!result.erroringRules.contains("no-extensions"))
    }

    @Test("a default implementation on a protocol this project declares is permitted")
    func protocolExtensionsArePermitted() throws {
        let result = try check("""
        extension ItemRepository {
            func first() async throws -> Item? { try await items().first }
        }
        """)
        #expect(!result.erroringRules.contains("no-extensions"))
    }

    @Test("a SwiftUI modifier is a protocol extension like any other")
    func platformProtocolExtensionsArePermitted() throws {
        let result = try check("""
        import SwiftUI

        public extension View {
            func catalogStyled() -> some View { padding() }
        }
        """, at: "UI/CatalogUI/Sources/UI/Styling.swift")
        #expect(!result.erroringRules.contains("no-extensions"))
    }

    @Test("a member available only under a constraint has nowhere else to go")
    func constrainedExtensionsArePermitted() throws {
        let result = try check("""
        public struct Boxed<Wrapped> {
            public let wrapped: Wrapped
        }

        extension Boxed where Wrapped == Item {
            public var name: String { wrapped.name }
        }
        """)
        #expect(!result.erroringRules.contains("no-extensions"))
    }

    @Test("extending somebody else's concrete type is exactly what this catches")
    func foreignConcreteTypesAreRefused() throws {
        let result = try check("""
        import Foundation

        extension String {
            var trimmedHard: String { trimmingCharacters(in: .whitespaces) }
        }
        """)
        #expect(result.erroringRules.contains("no-extensions"))
    }

    @Test("a test's own scaffolding is exempt, since it does not travel")
    func testsAreExempt() throws {
        let result = try check("""
        @testable import Catalog

        extension Item {
            static var sample: Item { Item(id: "1", name: "Kettle") }
        }
        """, at: "Component/Catalog/Tests/CatalogUnitTests/Samples.swift")
        #expect(!result.erroringRules.contains("no-extensions"))
    }
}

@Suite("Layer vocabulary")
struct LayerVocabularyTests {
    @Test("a domain protocol named for the wire is a domain service wearing the wrong word")
    func domainMayNotBorrowInfrastructureWords() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.write("Component/Catalog/Sources/Domain/Repository/PricingClient.swift", """
        public protocol PricingClient: Sendable {
            func price(of item: Item) async -> Int
        }
        """)

        let result = try fixture.check()
        #expect(result.warningRules.contains("layer-vocabulary"))
        // A judgement about wording, never a refusal.
        #expect(!result.erroringRules.contains("layer-vocabulary"))
    }

    @Test("the same word in the layer that owns the wire is fine")
    func dataMayNameItsOwnThings() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.write("Component/Catalog/Sources/Data/PricingClient.swift", """
        import Catalog

        public struct PricingClient: Sendable {
            public init() {}
        }
        """)

        #expect(!(try fixture.check().warningRules.contains("layer-vocabulary")))
    }
}

@Suite("Peer consistency")
struct PeerConsistencyTests {
    @Test("a package's own name is what makes two peers comparable")
    func normalisationErasesThePackageName() {
        #expect(
            PeerConsistencyRule.normalise("Tests/BagUnitTests/Support/Doubles.swift", name: "Bag")
                == "Tests/*UnitTests/Support/Doubles.swift"
        )
        #expect(PeerConsistencyRule.normalise("Sources/Domain/Bag.swift", name: "Bag") == "Sources/Domain/*.swift")
        #expect(
            PeerConsistencyRule.denormalise("Tests/*UnitTests/Support/Doubles.swift", name: "Order")
                == "Tests/OrderUnitTests/Support/Doubles.swift"
        )
    }

    @Test("a missing directory is not also reported as every file inside it")
    func impliedFeaturesAreCollapsed() {
        let absent: Set<String> = [
            "Sources/DI/",
            "Sources/DI/*DI.swift",
            "Tests/*UnitTests/Support/Doubles.swift"
        ]
        #expect(PeerConsistencyRule.outermost(absent) == ["Sources/DI/", "Tests/*UnitTests/Support/Doubles.swift"])
    }

    @Test("the odd package out is named, with the exact path it is missing")
    func reportsWhatTheMajorityHas() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        // Catalog already has a unit suite; give it doubles too, so that four
        // of the five siblings keep them beside their tests and one does not.
        try fixture.write(
            "Component/Catalog/Tests/CatalogUnitTests/Support/Doubles.swift",
            "struct FakeCatalog {}\n"
        )

        for name in ["Ledger", "Pricing", "Shipping", "Tax"] {
            try fixture.write("Component/\(name)/Package.swift", """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "\(name)",
                products: [.library(name: "\(name)", targets: ["\(name)"])],
                targets: [
                    .target(name: "\(name)", path: "Sources/Domain"),
                    .testTarget(name: "\(name)UnitTests", path: "Tests/\(name)UnitTests")
                ]
            )
            """)
            try fixture.write("Component/\(name)/Sources/Domain/\(name).swift", "public struct \(name) {}\n")
            try fixture.write(
                "Component/\(name)/Tests/\(name)UnitTests/\(name)Tests.swift",
                "import Testing\n\n@Test func placeholder() {}\n"
            )
            guard name != "Tax" else { continue }
            try fixture.write(
                "Component/\(name)/Tests/\(name)UnitTests/Support/Doubles.swift",
                "struct Fake\(name) {}\n"
            )
        }

        let result = try fixture.check()
        let found = result.warnings.filter { $0.rule == "peer-consistency" }

        // Tax has no `Support` directory at all, so that is the fact reported —
        // not the file inside it, which is implied.
        #expect(found.contains { $0.summary.contains("`Tax` has no `Tests/*UnitTests/Support/`") })
        #expect(found.contains { $0.fix?.contains("Component/Tax/Tests/TaxUnitTests/Support") == true })
        #expect(!found.contains { $0.summary.contains("Doubles.swift") })
        // The four that have it must not be reported.
        #expect(!found.contains { $0.summary.contains("`Ledger` has no `Tests/*UnitTests/Support/`") })
    }

    @Test("two packages disagreeing is not a convention with an exception")
    func tooFewPeersMeansNoOpinion() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.write("Component/Ledger/Package.swift", """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Ledger",
            products: [.library(name: "Ledger", targets: ["Ledger"])],
            targets: [.target(name: "Ledger", path: "Sources/Domain")]
        )
        """)
        try fixture.write("Component/Ledger/Sources/Domain/Ledger.swift", "public struct Ledger {}\n")

        #expect(!(try fixture.check().warningRules.contains("peer-consistency")))
    }
}
