import Foundation

/// The base of the shape is not narrower than what sits on it.
///
/// Which tier is the base is the project's decision, and `tests.pyramid` states
/// it. The default here is acceptance-first, which inverts the classic pyramid
/// on purpose: an architecture that tests through the domain's own vocabulary
/// puts the journeys underneath, because a test written against a journey
/// survives the feature being rearranged and a test written against a seam
/// breaks with the seam.
///
/// Reverse the list for the classic shape. Either way the rule is the same:
/// whatever the project says is the base should not be the smaller tier.
///
/// Compared only where both tiers actually exist — a package that owes a tier
/// and has none is a different complaint, and `tier-required` makes it.
public struct TestPyramidRule: Rule {
    public let identifier = "test-pyramid"
    public let defaultSeverity: Severity = .warning
    public var needsWholeProject: Bool { true }

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        let tests = context.configuration.tests
        guard tests.pyramid.count > 1 else { return [] }

        var counts: [String: [String: Int]] = [:]

        for file in context.files where file.role == .tests {
            guard let package = context.package(containing: file.path),
                  let tier = tests.tier(forFile: file.path),
                  !tests.isSupport(file.path) else { continue }
            counts[package, default: [:]][tier.name, default: 0] += file.facts.tests.count
        }

        var violations: [Violation] = []

        for package in counts.keys.sorted() {
            let byTier = counts[package]!
            for index in 0..<(tests.pyramid.count - 1) {
                let base = tests.pyramid[index]
                let above = tests.pyramid[index + 1]
                guard let baseCount = byTier[base], let aboveCount = byTier[above],
                      baseCount > 0, aboveCount > 0,
                      Double(baseCount) < Double(aboveCount) * tests.pyramidRatio else { continue }

                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: context.anchor(for: package),
                        line: nil,
                        summary: "\(context.label(for: package)) has \(aboveCount) `\(above)` tests "
                            + "against \(baseCount) `\(base)`, and `\(base)` is meant to be the wider tier",
                        fix: "`\(base)` is the base of this project's shape, so it should not be the "
                            + "smaller tier. Either the `\(base)` suite is missing cases that matter, or "
                            + "the `\(above)` suite has grown cases that belong beneath it. If the shape is "
                            + "wrong rather than the counts, `tests.pyramid` in the configuration is where "
                            + "the order is stated.",
                        source: Sources.testBoundary
                    )
                )
            }
        }

        return violations
    }
}
