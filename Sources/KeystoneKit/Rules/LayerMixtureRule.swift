import Foundation

/// One file, one layer.
///
/// A file that declares a screen and also opens a URL session is not a file
/// whose layer is unclear. It is two layers in one file, and no amount of
/// deciding which one it "really" is makes that better — the boundary the rest
/// of the architecture maintains between modules has been crossed inside a
/// single compilation unit, where nothing can see it. `dependency-rule` cannot
/// report this, because there is no import to read; `type-reference-boundary`
/// cannot, because there is no second declaration to point at.
///
/// The evidence is the platform's own vocabulary, read by `ContentMarkers`: a
/// conformance to `View`, an `@main`, an `NSManagedObject`, a `URLSession`. Two
/// of those in one file is the finding, and the report names both witnesses so
/// the reader does not have to hunt for what the tool saw.
///
/// Tests are exempt, and deliberately. A test may reach anywhere by design —
/// the preset gives the tests layer `mayDependOn: ["*"]` — so a suite that
/// drives a screen against a real store is doing its job, not breaking a rule.
///
/// A warning. Splitting a file is safe, mechanical and always available, but it
/// is refactoring rather than a broken boundary, and a migration has louder
/// problems first.
public struct LayerMixtureRule: Rule {
    public let identifier = "one-layer-per-file"
    public let defaultSeverity: Severity = .warning

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        var violations: [Violation] = []

        for file in context.files {
            // A test drives whatever it is testing. So does anything built to
            // serve one.
            if file.role?.isTestFacing == true { continue }

            let layers = ContentMarkers.layers(in: file.facts)
            guard layers.count > 1 else { continue }

            // The file may say it is a test even where the layer does not. A
            // project whose targets the tool cannot read — an XcodeGen one, say
            // — leaves its suites unclassified, and every `*Tests.swift` in it
            // then looked like a store mixed with a test. `import XCTest` is a
            // stronger statement about a file than a role nobody could derive.
            if layers.keys.contains(.tests) { continue }

            let named = layers.keys.sorted().map { "`\($0)`" }
            let evidence = layers.keys.sorted()
                .map { "\($0) from \(layers[$0]!)" }
                .joined(separator: ", ")

            violations.append(
                Violation(
                    rule: identifier,
                    severity: defaultSeverity,
                    file: file.path,
                    line: nil,
                    summary: "one file holds "
                        + named.dropLast().joined(separator: ", ")
                        + " and " + (named.last ?? "") + " code",
                    fix: "Split it. The tool read \(evidence). Two layers in one file cross a "
                        + "boundary where nothing can see it: no import records the crossing, so no "
                        + "rule about modules can report it, and the split that would make it "
                        + "visible is the one this file is avoiding.",
                    source: Sources.dependencyRule
                )
            )
        }

        return violations
    }
}
