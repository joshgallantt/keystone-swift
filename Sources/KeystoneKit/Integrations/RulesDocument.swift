import Foundation

/// The architecture, written out for whoever is about to change the code.
///
/// Generated from the configuration every time it is asked for, and never
/// committed. A checked-in copy is the failure this avoids: it drifts from the
/// file the checker reads while still sounding authoritative, and an agent
/// obeying a stale copy writes code the hook then refuses, which is the worst
/// of both. Reading a rule costs nothing; being refused costs a write and a
/// retry — so the cheap rung comes first.
public enum RulesDocument {
    public static func render(_ configuration: Configuration) -> String {
        var out: [String] = []

        out.append("# Architecture rules")
        out.append("")
        out.append(
            "These are enforced mechanically before every write. They are generated from "
            + "`\(ConfigurationLoader.fileName)`, which is the only place they are written down. "
            + "If a rule is wrong, the manifest is wrong — change it there, and say why in the "
            + "rule's `reason`."
        )
        out.append("")

        out.append("## Layers")
        out.append("")
        for (role, definition) in configuration.orderedRoles {
            out.append("### `\(role)`")
            out.append("")
            if let description = definition.description {
                out.append(description)
                out.append("")
            }
            if !definition.paths.isEmpty {
                out.append("- **Lives in** " + definition.paths.map { "`\($0)`" }.joined(separator: ", "))
            }
            out.append("- **May depend on** " + BoundaryPhrasing.permittedTargets(definition))
            if !definition.deniedFrameworks.isEmpty {
                out.append("- **Refuses frameworks** " + definition.deniedFrameworks.sorted().map { "`\($0)`" }.joined(separator: ", "))
            }
            if !definition.deniedSymbols.isEmpty {
                out.append("- **Refuses symbols** " + definition.deniedSymbols.sorted().map { "`\($0)`" }.joined(separator: ", "))
            }
            if !definition.allowsThirdParty {
                out.append("- **No third-party packages**")
            }
            switch definition.sameRole {
            case .allow:
                break
            case .deny:
                out.append("- **No sibling dependencies** — two `\(role)` modules may never depend on each other")
            case .denyAcrossPackages:
                out.append("- **No sibling dependencies across packages** — `\(role)` modules meet at the composition root")
            }
            if let reason = definition.reason {
                out.append("")
                out.append("> \(reason)")
            }
            out.append("")
        }

        if !configuration.conventions.isEmpty {
            out.append("## Where declarations go")
            out.append("")
            for convention in configuration.conventions.sorted(by: { $0.name < $1.name }) {
                out.append("- **\(convention.name)** — \(describe(convention.match)) belongs in "
                    + DeclarationPlacementRule.list(convention.requireRole) + ".")
                if let reason = convention.reason {
                    out.append("  \(reason)")
                }
            }
            out.append("")
        }

        if !configuration.extensionBoundaries.isEmpty {
            out.append("## Extensions")
            out.append("")
            for boundary in configuration.extensionBoundaries {
                let from = boundary.from.map { "`\($0)`" }.joined(separator: ", ")
                let declared = boundary.declaredIn.map { "`\($0)`" }.joined(separator: ", ")
                out.append("- \(from) may not extend types declared in \(declared).")
                if let reason = boundary.reason {
                    out.append("  \(reason)")
                }
            }
            out.append("")
        }

        out.append(contentsOf: testing(configuration))

        if !configuration.consistency.notes.isEmpty {
            out.append("## Differences already decided")
            out.append("")
            for note in configuration.consistency.notes {
                out.append("- \(note)")
            }
            out.append("")
        }

        out.append("## When a write is refused")
        out.append("")
        out.append(
            "The refusal names the layer, what it may reach instead, and where the code should go. "
            + "Move the code there rather than working around the rule: an import removed to satisfy "
            + "the check while the dependency stays is a worse state than the one you started in. "
            + "If the rule is genuinely wrong for this project, say so and change "
            + "`\(ConfigurationLoader.fileName)` — that is a decision worth making explicitly, in one place."
        )
        out.append("")

        return out.joined(separator: "\n")
    }

    /// The testing structure, which an agent needs *before* it writes a test.
    ///
    /// Left out of this document at first, which was a mistake worth recording:
    /// the layers were explained and the tiers were not, so an agent would
    /// write a test in the wrong place and find out from a refusal. Every rule
    /// this tool can enforce is cheaper as something the writer already knew.
    static func testing(_ configuration: Configuration) -> [String] {
        let tests = configuration.tests
        guard !tests.isEmpty else { return [] }

        var out: [String] = ["## Tests", ""]
        out.append(
            "Every test file belongs to a tier. A file directly inside a tier declares at least one "
            + "test; anything that helps tests rather than being one — a driver, a double, a builder — "
            + "goes in `\(tests.supportDirectory)/` beside the suite it serves."
        )
        out.append("")

        for tier in tests.tiers {
            out.append("### `\(tier.name)`")
            out.append("")
            out.append("- **Lives in** " + tier.paths.map { "`\($0)`" }.joined(separator: ", "))
            if !tier.requiredFor.isEmpty {
                out.append("- **Required of** " + tier.requiredFor.map(describe).joined(separator: "; "))
            }
            if tier.namesReadAsProse {
                out.append("- **Named in sentences** — `@Test(\"Someone who … ends up with …\")`, "
                    + "not an identifier")
            }
            if !tier.mayNotReference.isEmpty {
                let roles = tier.mayNotReference.map { "`\($0)`" }.joined(separator: ", ")
                out.append("- **May not name** any type declared in \(roles). Drive the feature through "
                    + "this tier's own vocabulary in `\(tests.supportDirectory)/` instead.")
            }
            if let artefacts = tier.artifactDirectory {
                out.append("- **Records to** `\(artefacts)/`, which must be committed — otherwise the "
                    + "suite writes its reference every run and compares it against itself.")
            }
            if let reason = tier.reason {
                out.append("")
                out.append("> \(reason)")
            }
            out.append("")
        }

        out.append("### Doubles and data")
        out.append("")
        out.append(
            "Test doubles are named for their kind — "
            + tests.doublePrefixes.map { "`\($0)*`" }.joined(separator: ", ")
            + " — because the kind tells the reader whether the test verifies state or behaviour. "
            + "No two doubles in the repository may share a name."
        )
        out.append("")
        out.append(
            "Use builders rather than a shared file of test data: one small type per thing the tests "
            + "need, where each test sets only the field it cares about. Data shared between tests is "
            + "owned by none of them, so nobody can change it safely."
        )
        out.append("")

        if tests.pyramid.count > 1 {
            out.append("Keep the base wider than what sits on it: "
                + tests.pyramid.map { "`\($0)`" }.joined(separator: " ≥ ") + ".")
            out.append("")
        }

        return out
    }

    static func describe(_ requirement: TierRequirement) -> String {
        let roles = requirement.roles.map { "`\($0)`" }.joined(separator: ", ")
        guard let declaring = requirement.declaring else { return "every \(roles) package" }
        // Only the first letter: lowercasing the whole phrase turned
        // `*ViewModel` into `*viewmodel`, which is a different type name.
        let phrase = describe(declaring)
        let opened = phrase.prefix(1).lowercased() + phrase.dropFirst()
        return "a \(roles) package declaring \(opened)"
    }

    static func describe(_ match: ConventionMatch) -> String {
        var parts: [String] = []
        if let kinds = match.kinds {
            let names = kinds.map { "`\($0.rawValue)`" }
            let list = names.count > 1
                ? names.dropLast().joined(separator: ", ") + " or " + names.last!
                : names.joined()
            parts.append("A \(list)")
        } else {
            parts.append("Anything")
        }
        if let suffix = match.nameSuffix { parts.append("named `*\(suffix)`") }
        if let prefix = match.namePrefix { parts.append("named `\(prefix)*`") }
        if let pattern = match.nameMatches { parts.append("matching `\(pattern)`") }
        return parts.joined(separator: " ")
    }
}
