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
