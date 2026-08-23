import Foundation

extension Commands {
    /// Where the project stands, rather than what is wrong with it.
    ///
    /// A migration needs a number that moves. `check` answers "may this land";
    /// this answers "how far through are we", which is the question anyone
    /// adopting the tool on an existing app will actually be asked.
    static func status(_ arguments: Arguments) -> Int32 {
        guard let project = Commands.resolveProject(arguments) else { return ExitCode.undecidable }

        let result = Checker().checkProject(root: project.root, configuration: project.configuration)
        let baseline = ConfigurationLoader.loadBaseline(root: project.root)
        let (fresh, accepted) = baseline?.partition(result.violations) ?? (result.violations, [])

        var lines: [String] = []
        lines.append("")
        lines.append(project.configuration.name ?? Paths.lastComponent(of: project.root))
        lines.append("")

        var counts: [Role: Int] = [:]
        for (_, role) in result.assignment.fileRoles { counts[role, default: 0] += 1 }
        let classified = counts.values.reduce(0, +)
        let unclassified = result.assignment.unclassifiedFiles.count

        lines.append("LAYERS")
        for (role, definition) in project.configuration.orderedRoles {
            let count = counts[role] ?? 0
            let paths = definition.paths.isEmpty ? "no paths declared" : definition.paths.joined(separator: ", ")
            lines.append("  \(pad(role.rawValue, 14)) \(pad("\(count)", 6)) files   \(paths)")
        }
        if unclassified > 0 {
            lines.append("  \(pad("unclassified", 14)) \(pad("\(unclassified)", 6)) files   not examined by any rule")
        }

        let coverage = classified + unclassified == 0
            ? 100
            : Int((Double(classified) / Double(classified + unclassified) * 100).rounded())
        lines.append("")
        lines.append("  \(coverage)% of Swift files are inside the architecture.")

        lines.append("")
        lines.append("VIOLATIONS")
        let byRule = Dictionary(grouping: result.violations, by: \.rule)
        if byRule.isEmpty {
            lines.append("  none")
        } else {
            for rule in byRule.keys.sorted() {
                let all = byRule[rule]!
                let new = all.filter { violation in
                    fresh.contains { $0.file == violation.file && $0.rule == violation.rule && $0.summary == violation.summary }
                }.count
                let suffix = baseline == nil ? "" : "   (\(new) new, \(all.count - new) accepted)"
                lines.append("  \(pad(rule, 30)) \(pad("\(all.count)", 5))\(suffix)")
            }
        }

        if let baseline {
            let resolved = baseline.resolved(against: result.violations)
            lines.append("")
            lines.append("DEBT")
            lines.append("  \(accepted.count) accepted, \(fresh.count) new since the baseline was recorded.")
            if !resolved.isEmpty {
                lines.append("  \(resolved.count) baselined violations no longer occur — "
                    + "run `keystone-swift baseline` to bank that progress.")
            }
        } else {
            lines.append("")
            lines.append("No baseline recorded. `keystone-swift baseline` accepts today's \(result.violations.count) "
                + "violations as existing debt so that only new work is held to the rules.")
        }

        lines.append("")
        Output.print(lines.joined(separator: "\n"))
        return ExitCode.clean
    }
}
