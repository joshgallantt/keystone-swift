import Foundation

extension Commands {
    /// Answers "is this thing actually switched on", which is the first
    /// question when a rule fails to fire and the last one anybody thinks of.
    static func doctor(_ arguments: Arguments) -> Int32 {
        let root = arguments.root
        var lines: [String] = [""]
        var healthy = true

        lines.append(Version.current)
        lines.append("")

        if let path = ConfigurationLoader.discover(from: root) {
            lines.append("configuration   \(Paths.relative(path, to: root))")
            do {
                let configuration = try ConfigurationLoader.load(at: path)
                let withoutPaths = configuration.orderedRoles.filter { $0.definition.paths.isEmpty }
                lines.append("layers          \(configuration.roles.count) declared")
                if !withoutPaths.isEmpty {
                    healthy = false
                    lines.append("                \(withoutPaths.map { $0.name.rawValue }.joined(separator: ", "))"
                        + " claim no paths, so they match nothing")
                }
                lines.append("rules           \(RuleRegistry.identifiers.count) available, "
                    + "\(configuration.disabledRules.count) disabled")
            } catch {
                healthy = false
                lines.append("                \(error)")
            }
        } else {
            healthy = false
            lines.append("configuration   not found — run `keystone-swift init`")
        }

        let baselinePath = Paths.join(root, ConfigurationLoader.baselineFileName)
        if let baseline = ConfigurationLoader.loadBaseline(root: root) {
            lines.append("baseline        \(baseline.entries.count) accepted violations")
        } else if FileManager.default.fileExists(atPath: baselinePath) {
            healthy = false
            lines.append("baseline        present but unreadable")
        } else {
            lines.append("baseline        none")
        }

        lines.append("")
        lines.append("INTEGRATIONS")
        lines.append("  claude code   " + ClaudeInstaller.describe(root: root))
        lines.append("  kiro          " + KiroInstaller.describe(root: root))
        lines.append("  github ci     " + CIInstaller.describe(root: root))

        lines.append("")
        lines.append("  git           " + (Git.isRepository(root) ? "repository found" : "not a repository — --changed will not work"))
        lines.append("")

        Output.print(lines.joined(separator: "\n"))
        return healthy ? ExitCode.clean : ExitCode.undecidable
    }
}
