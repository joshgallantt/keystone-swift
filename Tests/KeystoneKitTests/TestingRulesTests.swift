import Foundation
import Testing
@testable import KeystoneKit

@Suite("Test tiers")
struct TestTierRuleTests {
    @Test("a project with no packages is still held to its tiers")
    func aSingleTargetAppOwesTiersToo() throws {
        let fixture = try Fixture.load("MonolithApp")
        defer { fixture.destroy() }

        // The case that needs these rules most: one Xcode target and some
        // folders. Grouping by package would have skipped it entirely.
        try fixture.remove("Tests")

        let violations = try fixture.check().errors.filter { $0.rule == "tier-required" }
        #expect(violations.contains { $0.summary.contains("`acceptance` suite") })
        #expect(violations.contains { $0.summary.contains("`unit` suite") })
        #expect(violations.first?.fix?.contains("Tests/AppUnitTests/") == true
            || violations.last?.fix?.contains("Tests/AppUnitTests/") == true)
    }

    @Test("a package with views owes a snapshot suite, and one without does not")
    func snapshotTiersAreEarnedByHavingViews() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.remove("UI/CatalogUI/Tests/CatalogUISnapshotTests")

        let violations = try fixture.check().errors.filter { $0.rule == "tier-required" }
        #expect(violations.contains { $0.summary.contains("`CatalogUI` has no `snapshot` suite") })
        // The domain component has no views, so it is not asked for one.
        #expect(!violations.contains { $0.summary.contains("`Catalog` has no `snapshot` suite") })
    }

    @Test("a test file in no declared tier is refused")
    func strayTestTargetsAreRefused() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.write("Component/Catalog/Tests/CatalogIntegrationTests/WiringTests.swift", """
        import Testing

        @Test("something") func something() {}
        """)

        #expect(try fixture.check().erroringRules.contains("test-tiers"))
    }
}

@Suite("Support separation")
struct TestSupportRuleTests {
    @Test("a test hidden in Support is refused")
    func supportMayNotHoldTests() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.write("Component/Catalog/Tests/CatalogUnitTests/Support/SneakyTests.swift", """
        import Testing

        @Test("hidden away") func hiddenAway() {}
        """)

        #expect(try fixture.check().erroringRules.contains("support-separation"))
    }

    @Test("a helper sitting among the tests is refused")
    func tierFilesMustAssertSomething() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.write("Component/Catalog/Tests/CatalogUnitTests/Helpers.swift", """
        struct Helper {
            static func makeSomething() -> Int { 1 }
        }
        """)

        #expect(try fixture.check().erroringRules.contains("tests-assert-something"))
    }
}

@Suite("Test doubles")
struct TestDoubleRuleTests {
    @Test("a double declared among the tests is refused")
    func doublesBelongInSupport() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.append("Component/Catalog/Tests/CatalogUnitTests/ItemTests.swift", """

        struct SpyRecorder {
            var calls = 0
        }
        """)

        #expect(try fixture.check().erroringRules.contains("doubles-live-in-support"))
    }

    @Test("two doubles sharing a visible name are reported")
    func duplicateVisibleDoublesAreReported() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.write("Component/Catalog/Tests/CatalogAcceptanceTests/Support/More.swift", """
        struct StubPopulatedCatalog {
            let items: [String] = []
        }
        """)

        let result = try fixture.check()
        // Never an error: Swift already refuses two of a name in one module, so
        // every duplicate this can find is in another module and cannot collide.
        #expect(result.warningRules.contains("doubles-are-uniquely-named"))
        #expect(!result.erroringRules.contains("doubles-are-uniquely-named"))
        #expect(result.warnings.contains { $0.rule == "doubles-are-uniquely-named"
            && $0.summary.contains("is declared 2 times") })
    }

    @Test("file-private copies are named as repetition rather than as a name clash")
    func duplicatePrivateDoublesReadDifferently() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        // Nothing can collide: each copy is invisible outside its own file, in
        // its own module. What is left is the same double written twice.
        try fixture.write("Component/Catalog/Tests/CatalogUnitTests/Support/Doubles.swift", """
        private struct StubClock {
            let now = 0
        }
        """)
        try fixture.write("Component/Catalog/Tests/CatalogAcceptanceTests/Support/Clock.swift", """
        private struct StubClock {
            let now = 0
        }
        """)

        let found = try fixture.check().warnings.filter { $0.rule == "doubles-are-uniquely-named" }
        #expect(found.contains { $0.summary.contains("written 2 times over, each one file-private") })
        #expect(found.contains { $0.fix?.contains("not a naming problem but a repetition one") == true })
    }
}

@Suite("Acceptance suites")
struct AcceptanceRuleTests {
    @Test("an acceptance test naming something the data layer declared is refused")
    func acceptanceTestsSpeakTheBusinessLanguage() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.write("Component/Catalog/Tests/CatalogAcceptanceTests/LeakyTests.swift", """
        import CatalogData
        import Testing

        @Test("A person browsing sees what is on offer")
        func aPersonSeesWhatIsOnOffer() async throws {
            let repository = DefaultItemRepository(client: StubClient())
            #expect(try await repository.items().isEmpty)
        }
        """)

        #expect(try fixture.check().erroringRules.contains("acceptance-vocabulary"))
    }

    @Test("the driver may name concrete types, because that is what it is for")
    func supportIsExemptFromTheVocabularyRule() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        // The existing Support/ files already reach for domain types; adding a
        // data type there must stay silent while the same reference in a test
        // does not.
        try fixture.write("Component/Catalog/Tests/CatalogAcceptanceTests/Support/Wiring.swift", """
        import CatalogData

        struct Wiring {
            let repository = DefaultItemRepository(client: StubHTTP())
        }

        struct StubHTTP {}
        """)

        #expect(!(try fixture.check().erroringRules.contains("acceptance-vocabulary")))
    }

    @Test("a business-facing test named as an identifier is refused")
    func acceptanceNamesMustReadAsProse() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.write("Component/Catalog/Tests/CatalogAcceptanceTests/TerseTests.swift", """
        import Testing

        @Test func catalogFlow2() {}
        """)

        #expect(try fixture.check().erroringRules.contains("test-names-read-as-prose"))
    }

    @Test("the unit tier is not held to prose names")
    func unitNamesAreNotHeldToProse() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.write("Component/Catalog/Tests/CatalogUnitTests/TerseTests.swift", """
        import Testing

        @Test func itemIdentityIsStable() {}
        """)

        #expect(!(try fixture.check().erroringRules.contains("test-names-read-as-prose")))
    }
}

@Suite("Testing hygiene")
struct TestingHygieneTests {
    @Test("a file of shared test data is reported")
    func sharedFixturesAreReported() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.write("Component/Catalog/Tests/CatalogUnitTests/Support/Fixtures.swift", """
        enum Fixtures {
            static let name = "Kettle"
        }
        """)

        #expect(try fixture.check().warningRules.contains("no-shared-fixtures"))
    }

    @Test("more journeys than unit tests is reported")
    func aninvertedPyramidIsReported() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.write("Component/Catalog/Tests/CatalogAcceptanceTests/MoreTests.swift", """
        import Testing

        @Test("Someone browsing twice sees the same thing both times")
        func browsingTwiceIsStable() {}

        @Test("Someone browsing an empty store is told so")
        func browsingNothingSaysSo() {}

        @Test("Someone browsing after a change sees the change")
        func browsingAfterAChangeShowsIt() {}
        """)

        #expect(try fixture.check().warningRules.contains("test-pyramid"))
    }

    @Test("a snapshot suite with nothing recorded has never been able to fail")
    func uncommittedSnapshotsAreReported() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.remove("UI/CatalogUI/Tests/CatalogUISnapshotTests/__Snapshots__")

        #expect(try fixture.check().warningRules.contains("snapshots-are-committed"))
    }
}
