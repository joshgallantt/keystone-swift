import Foundation

/// The base of the pyramid is not narrower than what sits on it.
///
/// A package with forty acceptance journeys and six unit tests has its testing
/// upside down: the suite is slow, every failure implicates the whole feature,
/// and no failure says which rule is wrong. Compared only where both tiers
/// actually exist — a package that owes a tier and has none is a different
/// complaint, and `tier-required` makes it.
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
                      baseCount > 0, aboveCount > 0, baseCount < aboveCount else { continue }

                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: context.anchor(for: package),
                        line: nil,
                        summary: "\(context.label(for: package)) has \(aboveCount) `\(above)` tests "
                            + "and only \(baseCount) `\(base)` tests",
                        fix: "Push the detail downward. Cases that differ only in a rule belong in the "
                            + "`\(base)` tier, where the failure names the rule; the `\(above)` tier should "
                            + "hold one journey per thing the business can do, not one per branch of the "
                            + "logic behind it.",
                        source: Sources.testBoundary
                    )
                )
            }
        }

        return violations
    }
}
