import Foundation

extension Commands {
    static func rules(_ arguments: Arguments) -> Int32 {
        guard let project = Commands.resolveProject(arguments) else { return ExitCode.undecidable }

        if arguments.has("list") {
            Output.print(Commands.ruleList(project.configuration))
            return ExitCode.clean
        }

        Output.write(RulesDocument.render(project.configuration))
        return ExitCode.clean
    }

    /// Every rule, its severity here, and whether it runs — so that switching
    /// one on is a thing you can check rather than hope for.
    static func ruleList(_ configuration: Configuration) -> String {
        var lines = [""]
        let whitelisted = !configuration.enabledRules.isEmpty
        if whitelisted {
            lines.append("Only the rules listed in `enabledRules` run. \(configuration.enabledRules.count) of "
                + "\(RuleRegistry.identifiers.count) are on.")
            lines.append("")
        }

        // One line per identifier, not per rule: two rules can report under
        // the same name, and a listing that showed it twice would read as two
        // things to switch off.
        var seen: Set<String> = []
        for rule in RuleRegistry.all {
            for identifier in rule.emittedIdentifiers.sorted() where seen.insert(identifier).inserted {
                let on = configuration.isEnabled(identifier)
                let severity = configuration.severity(
                    for: identifier,
                    default: rule.defaultSeverity(for: identifier)
                )
                let mark = on ? (severity == .error ? "error  " : "warning") : "off    "
                lines.append("  \(mark)  \(identifier)")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }
}
