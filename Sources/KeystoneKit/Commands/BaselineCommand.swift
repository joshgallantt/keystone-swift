import Foundation

extension Commands {
    static func baseline(_ arguments: Arguments) -> Int32 {
        guard let project = Commands.resolveProject(arguments) else { return ExitCode.undecidable }

        let result = Checker().checkProject(root: project.root, configuration: project.configuration)
        let previous = ConfigurationLoader.loadBaseline(root: project.root)
        let updated = Baseline.record(result.violations)
        let path = Paths.join(project.root, ConfigurationLoader.baselineFileName)

        if arguments.has("dry-run") {
            Output.print("Would record \(updated.entries.count) violations as accepted debt in "
                + "\(ConfigurationLoader.baselineFileName).")
            return ExitCode.clean
        }

        do {
            try ConfigurationLoader.write(updated, to: path)
        } catch {
            Output.error("Could not write \(path): \(error)")
            return ExitCode.undecidable
        }

        if let previous {
            let removed = previous.entries.count - updated.entries.count
            let resolved = previous.resolved(against: result.violations).count
            Output.print("Recorded \(updated.entries.count) accepted violations "
                + "(was \(previous.entries.count)). \(resolved) fixed since the last baseline.")
            if removed < 0 {
                Output.print("The total went up by \(-removed). New violations are being accepted rather than "
                    + "fixed — worth a look at what `keystone-swift check` reported before this ran.")
            }
        } else {
            Output.print("Recorded \(updated.entries.count) accepted violations in "
                + "\(ConfigurationLoader.baselineFileName).")
            Output.print("")
            Output.print("Commit it. From here `keystone-swift check` reports only what is new, so the number "
                + "can go down but not up. Re-run this command whenever you want to bank progress.")
        }

        return ExitCode.clean
    }
}
