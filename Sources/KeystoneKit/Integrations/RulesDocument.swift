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

    static func describe(_ match: ConventionMatch) -> String {
        var parts: [String] = []
        if let kinds = match.kinds {
            parts.append("A " + kinds.map { "`\($0.rawValue)`" }.joined(separator: " or "))
        } else {
            parts.append("Anything")
        }
        if let suffix = match.nameSuffix { parts.append("named `*\(suffix)`") }
        if let prefix = match.namePrefix { parts.append("named `\(prefix)*`") }
        if let pattern = match.nameMatches { parts.append("matching `\(pattern)`") }
        return parts.joined(separator: " ")
    }
}
