import Foundation
import Testing
@testable import KeystoneKit

@Suite("Globs")
struct GlobTests {
    @Test("a single star stops at a separator and a double star does not")
    func starsRespectSeparators() {
        #expect(Glob("Sources/*/File.swift").matches("Sources/App/File.swift"))
        #expect(!Glob("Sources/*/File.swift").matches("Sources/App/Deep/File.swift"))
        #expect(Glob("Sources/**").matches("Sources/App/Deep/File.swift"))
    }

    @Test("a leading double-star segment also matches nothing at all")
    func leadingDoubleStarMatchesTheRoot() {
        #expect(Glob("**/Tests/**").matches("Tests/AppTests/File.swift"))
        #expect(Glob("**/Tests/**").matches("Deep/Nested/Tests/File.swift"))
    }

    @Test("wildcards are captured so a destination can be built from them")
    func capturesCarryAcrossPatterns() {
        let captures = Glob("Component/*/Sources/Data/**").captures("Component/Bag/Sources/Data/Repo.swift")
        #expect(captures?.first == "Bag")

        let filled = Glob.fill("Component/*/Sources/Domain/**", with: captures ?? [])
        #expect(filled == "Component/Bag/Sources/Domain/Repo.swift")
    }

    @Test("an empty set matches nothing rather than everything")
    func emptySetMatchesNothing() {
        #expect(!GlobSet([]).matches("anything/at/all.swift"))
    }
}

@Suite("Paths")
struct PathsTests {
    @Test("a root and its files agree even when macOS spells one with /private")
    func relativeHandlesThePrivatePrefix() {
        #expect(Paths.relative("/private/var/x/App/File.swift", to: "/var/x") == "App/File.swift")
        #expect(Paths.relative("/var/x/App/File.swift", to: "/private/var/x") == "App/File.swift")
        #expect(Paths.relative("/var/x/App/File.swift", to: "/var/x") == "App/File.swift")
    }

    @Test("a path outside the root is left absolute rather than mangled")
    func unrelatedPathsAreUntouched() {
        #expect(Paths.relative("/elsewhere/File.swift", to: "/var/x") == "/elsewhere/File.swift")
    }

    @Test("dot segments are resolved without touching the disk")
    func normaliseResolvesTraversal() {
        #expect(Paths.normalise("Component/Bag/../Order/Sources") == "Component/Order/Sources")
        #expect(Paths.normalise("./Sources/./Domain") == "Sources/Domain")
    }
}

@Suite("Property lists")
struct OpenStepPlistTests {
    @Test("the pbxproj dialect parses, comments and all")
    func parsesTheXcodeDialect() {
        let text = """
        // !$*UTF8*$!
        {
            archiveVersion = 1;
            objects = {
                ABC123 /* MyApp */ = {
                    isa = PBXNativeTarget;
                    name = "My App";
                    buildPhases = (
                        DEF456 /* Sources */,
                    );
                };
            };
        }
        """

        let value = OpenStepPlist.parse(text)
        let target = value?["objects"]?["ABC123"]
        #expect(target?["isa"]?.stringValue == "PBXNativeTarget")
        #expect(target?["name"]?.stringValue == "My App")
        #expect(target?["buildPhases"]?.stringArray == ["DEF456"])
    }

    @Test("escapes inside quoted strings survive")
    func handlesEscapes() {
        let value = OpenStepPlist.parse(#"{ path = "a\"b"; }"#)
        #expect(value?["path"]?.stringValue == #"a"b"#)
    }
}

@Suite("Package manifests")
struct PackageManifestParserTests {
    @Test("sources and exclude decide a target's real directories")
    func sourcesOverrideThePath() {
        let manifest = """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Catalog",
            targets: [
                .target(name: "Catalog", path: "Sources", exclude: ["Data", "DI"], sources: ["Domain"]),
                .target(name: "CatalogDI", dependencies: ["Catalog"], path: "Sources/DI")
            ]
        )
        """

        let parsed = PackageManifestParser().parse(
            source: manifest,
            manifestPath: "Component/Catalog/Package.swift",
            root: "/nowhere"
        )

        let domain = parsed?.targets.first { $0.name == "Catalog" }
        #expect(domain?.sourceRoots == ["Component/Catalog/Sources/Domain"])
        #expect(domain?.excludedPaths == ["Component/Catalog/Sources/Data", "Component/Catalog/Sources/DI"])

        let wiring = parsed?.targets.first { $0.name == "CatalogDI" }
        #expect(wiring?.sourceRoots == ["Component/Catalog/Sources/DI"])
        #expect(wiring?.declaredDependencies == ["Catalog"])
    }

    @Test("all four spellings of a target dependency are understood")
    func readsEveryDependencyForm() {
        let manifest = """
        import PackageDescription

        let package = Package(
            name: "App",
            dependencies: [.package(url: "https://github.com/x/Alamofire.git", from: "5.0.0")],
            targets: [
                .target(name: "App", dependencies: [
                    "Bare",
                    .product(name: "Alamofire", package: "Alamofire"),
                    .target(name: "Sibling"),
                    .byName(name: "Named")
                ])
            ]
        )
        """

        let parsed = PackageManifestParser().parse(source: manifest, manifestPath: "Package.swift", root: "/nowhere")
        #expect(parsed?.targets.first?.declaredDependencies == ["Bare", "Alamofire", "Sibling", "Named"])
        #expect(parsed?.externalPackages == ["Alamofire"])
    }

    @Test("a manifest that computes its targets yields nothing rather than a guess")
    func declinesToGuess() {
        let manifest = """
        import PackageDescription
        let names = ["A", "B"]
        let package = Package(name: "App", targets: names.map { .target(name: $0) })
        """

        let parsed = PackageManifestParser().parse(source: manifest, manifestPath: "Package.swift", root: "/nowhere")
        #expect(parsed?.targets.isEmpty == true)
    }
}

@Suite("Reading Swift")
struct SwiftSourceAnalyzerTests {
    let analyzer = SwiftSourceAnalyzer()

    @Test("imports are read down to the module, however they are written")
    func readsEveryImportForm() {
        let facts = analyzer.analyze(path: "F.swift", content: """
        import Foundation
        @testable import Catalog
        import struct Money.Currency
        @preconcurrency import Combine
        """)

        #expect(facts.imports.map(\.module) == ["Foundation", "Catalog", "Money", "Combine"])
        #expect(facts.imports[1].isTestable)
    }

    @Test("a nested type is not mistaken for a top-level one")
    func tracksNesting() {
        let facts = analyzer.analyze(path: "F.swift", content: """
        public struct Outer {
            struct InnerViewModel {}
        }
        """)

        #expect(facts.declarations.first { $0.name == "Outer" }?.isTopLevel == true)
        #expect(facts.declarations.first { $0.name == "InnerViewModel" }?.isTopLevel == false)
    }

    @Test("an extension is attributed to the type it reopens, qualified or not")
    func readsExtensions() {
        let facts = analyzer.analyze(path: "F.swift", content: """
        extension Order {}
        extension Money.Currency {}
        extension SwiftUI.View {}
        """)

        // The rightmost component. `Money.Currency` reopens `Currency`, and the
        // qualifier is the module it lives in — which is what this test's name
        // has always said and what the assertion, written as a map onto
        // `["Order", "Money"]`, quietly did not check.
        #expect(facts.extensions.map(\.name) == ["Order", "Currency", "View"])
    }

    @Test("access level and conformances are recorded")
    func readsModifiersAndConformances() {
        let facts = analyzer.analyze(path: "F.swift", content: """
        public struct DefaultThing: Thing, Sendable {}
        struct Quiet {}
        """)

        let thing = facts.declarations.first { $0.name == "DefaultThing" }
        #expect(thing?.accessLevel == .public)
        #expect(thing?.inheritedTypes == ["Thing", "Sendable"])
        #expect(facts.declarations.first { $0.name == "Quiet" }?.accessLevel == .internal)
    }

    @Test("a marker inside a string literal is not a comment")
    func distinguishesCommentsFromStrings() {
        let facts = analyzer.analyze(path: "F.swift", content: """
        let banner = "TODO: not a note"
        // TODO: a real note
        """)

        #expect(facts.comments.count == 1)
        #expect(facts.comments.first?.text.contains("a real note") == true)
    }

    @Test("static members are recorded so a shared instance can be found")
    func recordsStaticMembers() {
        let facts = analyzer.analyze(path: "F.swift", content: """
        enum Registry {
            static let shared = 1
            let notStatic = 2
        }
        """)

        #expect(facts.declarations.contains { $0.name == "shared" && $0.isStatic })
        #expect(!facts.declarations.contains { $0.name == "notStatic" })
    }
}

@Suite("Baselines")
struct BaselineTests {
    let violation = Violation(
        rule: "dependency-rule",
        severity: .error,
        file: "A.swift",
        line: 3,
        summary: "`domain` imports `AppData`, which belongs to `data`"
    )

    @Test("an accepted violation stops being reported")
    func acceptedViolationsAreSeparated() {
        let baseline = Baseline.record([violation])
        let (fresh, accepted) = baseline.partition([violation])

        #expect(fresh.isEmpty)
        #expect(accepted.count == 1)
    }

    @Test("moving a violation down a file does not resurrect it")
    func lineNumbersAreNotPartOfIdentity() {
        let baseline = Baseline.record([violation])
        var moved = violation
        moved.line = 91

        #expect(baseline.partition([moved]).fresh.isEmpty)
    }

    @Test("a new violation in an already-indebted file is still reported")
    func newViolationsSurfaceThroughTheBaseline() {
        let baseline = Baseline.record([violation])
        var different = violation
        different.summary = "`domain` imports `SwiftUI`, a `ui` framework it refuses"

        #expect(baseline.partition([different]).fresh.count == 1)
    }

    @Test("fixing a violation shows up as resolved")
    func resolvedEntriesAreReported() {
        let baseline = Baseline.record([violation])
        #expect(baseline.resolved(against: []).count == 1)
        #expect(baseline.resolved(against: [violation]).isEmpty)
    }
}
