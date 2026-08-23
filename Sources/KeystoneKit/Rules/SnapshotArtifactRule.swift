import Foundation

/// A snapshot suite with nothing recorded has never asserted anything.
///
/// Snapshot tests pass on their first run by writing the reference image, and
/// pass forever after if nobody commits it — the recording is regenerated each
/// time and compared against itself. A suite in that state is green, runs in CI,
/// and has never once been capable of failing. Checking that the artefacts are
/// in the repository is the only way to tell the two apart from the outside.
public struct SnapshotArtifactRule: Rule {
    public let identifier = "snapshots-are-committed"
    public let defaultSeverity: Severity = .warning
    public var needsWholeProject: Bool { true }

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        let tests = context.configuration.tests
        guard !tests.isEmpty else { return [] }

        var violations: [Violation] = []

        for tier in tests.tiers {
            guard let artefacts = tier.artifactDirectory else { continue }

            var packagesWithTier: Set<String> = []
            for file in context.files where file.role == .tests {
                guard tests.tier(forFile: file.path)?.name == tier.name,
                      !tests.isSupport(file.path),
                      !file.facts.tests.isEmpty,
                      let package = context.package(containing: file.path) else { continue }
                packagesWithTier.insert(package)
            }

            for package in packagesWithTier.sorted() {
                let recorded = context.allFiles.contains { path in
                    context.contains(path, in: package)
                        && path.split(separator: "/").contains(Substring(artefacts))
                }
                guard !recorded else { continue }

                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: context.anchor(for: package),
                        line: nil,
                        summary: "\(context.label(for: package)) has a `\(tier.name)` suite but no "
                            + "committed `\(artefacts)`",
                        fix: "Record the snapshots and commit `\(artefacts)/`. Until they are in the "
                            + "repository the suite writes its reference on every run and compares it "
                            + "against itself, so it is green in CI and has never been able to fail. Check "
                            + "the images by eye once, then let them hold the line.",
                        source: nil
                    )
                )
            }
        }

        return violations
    }
}
