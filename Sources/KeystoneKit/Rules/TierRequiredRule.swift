import Foundation

/// Whoever owes a tier has one.
///
/// Requirements are conditional because the honest rule is conditional. Every
/// component owes an acceptance suite and a unit suite. A feature package earns
/// a unit tier by having a view model and a snapshot tier by having a view —
/// a package of nothing but views has no unit for a unit test to name, and
/// demanding one produces ceremony rather than coverage.
public struct TierRequiredRule: Rule {
    public let identifier = "tier-required"
    public let defaultSeverity: Severity = .error
    public var needsWholeProject: Bool { true }

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        let tests = context.configuration.tests
        guard !tests.isEmpty else { return [] }

        var filesByPackage: [String: [AnalyzedFile]] = [:]
        for file in context.files {
            guard let package = context.package(containing: file.path) else { continue }
            filesByPackage[package, default: []].append(file)
        }

        var violations: [Violation] = []

        for package in filesByPackage.keys.sorted() {
            let files = filesByPackage[package]!

            for tier in tests.tiers {
                guard let requirement = TierRequiredRule.requirement(tier, satisfiedBy: files) else { continue }
                guard !files.contains(where: { tests.tier(forFile: $0.path)?.name == tier.name }) else { continue }

                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: context.anchor(for: package),
                        line: nil,
                        summary: "\(context.label(for: package)) has no `\(tier.name)` suite",
                        fix: requirement.reason ?? tier.reason ?? TierRequiredRule.advice(
                            tier: tier,
                            package: package
                        ),
                        source: Sources.testBoundary
                    )
                )
            }
        }

        return violations
    }

    /// The first condition this package meets, if any.
    static func requirement(_ tier: TestTier, satisfiedBy files: [AnalyzedFile]) -> TierRequirement? {
        tier.requiredFor.first { requirement in
            let candidates = files.filter { file in
                guard let role = file.role else { return false }
                return requirement.roles.contains(role)
            }
            guard !candidates.isEmpty else { return false }
            guard let declaring = requirement.declaring else { return true }

            return candidates.contains { file in
                file.facts.declarations.contains { declaration in
                    declaration.isTopLevel && DeclarationPlacementRule.matches(declaration, declaring)
                }
            }
        }
    }

    static func advice(tier: TestTier, package: String) -> String {
        let where_ = TierRequiredRule.example(tier: tier, package: package).map { " at `\($0)`" } ?? ""
        return "Add a `\(tier.name)` suite\(where_). Code without one is not untested so much as "
            + "unexamined in one particular way, and which way that is tends to be discovered during an "
            + "incident rather than during a review."
    }

    /// A real directory to create, built from the tier's own path pattern.
    ///
    /// `Glob.fill` cannot do this alone: the pattern starts `**/`, so filling
    /// wildcards left to right puts the package's name where the leading path
    /// goes and produces `App/Tests/*UnitTests/`. Trimming the anchoring
    /// wildcards first leaves `Tests/*UnitTests`, which is the part that
    /// actually describes the directory.
    static func example(tier: TestTier, package: String) -> String? {
        guard let pattern = tier.paths.first else { return nil }
        let name = package.isEmpty ? "App" : Paths.lastComponent(of: package)

        var segments = pattern.split(separator: "/").map(String.init)
        while segments.first == "**" { segments.removeFirst() }
        while segments.last == "**" { segments.removeLast() }
        guard !segments.isEmpty else { return nil }

        let filled = segments.map { $0.replacingOccurrences(of: "*", with: name) }
        return Paths.join(package, filled.joined(separator: "/")) + "/"
    }
}
