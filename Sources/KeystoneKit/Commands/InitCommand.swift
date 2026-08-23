import Foundation

extension Commands {
    static func initialise(_ arguments: Arguments) -> Int32 {
        let root = arguments.root
        let destination = arguments.value("config") ?? Paths.join(root, ConfigurationLoader.fileName)

        if FileManager.default.fileExists(atPath: destination), !arguments.has("force") {
            Output.error("\(destination) already exists. Pass --force to replace it, or edit it directly — "
                + "once written, this file is yours rather than the tool's.")
            return ExitCode.undecidable
        }

        let report = RoleInference().infer(root: root)

        Output.print("")
        Output.print("Read \(report.modules.count) modules in \(Paths.lastComponent(of: root)).")
        Output.print("")
        Output.print(table(report))

        if !report.unclassifiedFiles.isEmpty {
            Output.print("")
            Output.print("\(report.unclassifiedFiles.count) files belong to no layer yet. They are reported as "
                + "warnings until a layer claims them or `exclude` disowns them — the tool will not pretend to "
                + "have checked a file it never looked at. The first few:")
            for path in report.unclassifiedFiles.prefix(8) {
                Output.print("  \(path)")
            }
        }

        if arguments.has("dry-run") {
            Output.print("")
            Output.print("Nothing written (--dry-run).")
            return ExitCode.clean
        }

        do {
            try ConfigurationLoader.write(report.configuration, to: destination)
        } catch {
            Output.error("Could not write \(destination): \(error)")
            return ExitCode.undecidable
        }

        Output.print("")
        Output.print("Wrote \(Paths.relative(destination, to: root)).")
        Output.print("")
        Output.print("""
        Read it before you trust it. Everything above was inferred from directory names, imports and \
        the module graph, and inference runs exactly once — from here on the checker reads only this \
        file, so a wrong guess left in it becomes a wrong rule.

        Then:
          keystone-swift check              see where the project stands today
          keystone-swift baseline           accept that as existing debt, so only new work is held to it
          keystone-swift install claude     refuse violating writes before they land
        """)

        return ExitCode.clean
    }

    static func table(_ report: InferenceReport) -> String {
        var lines: [String] = []
        let nameWidth = max(6, report.modules.map(\.name.count).max() ?? 6)
        let roleWidth = 13

        lines.append(pad("MODULE", nameWidth) + "  " + pad("LAYER", roleWidth) + "  FILES  WHY")
        for finding in report.modules.sorted(by: { $0.name < $1.name }) {
            let role = finding.role.map(\.rawValue) ?? "—"
            lines.append(
                pad(finding.name, nameWidth) + "  " + pad(role, roleWidth)
                + "  " + pad("\(finding.fileCount)", 5) + "  " + finding.evidence
            )
        }

        lines.append("")
        for (role, patterns) in report.directories {
            let count = report.fileCounts[role] ?? 0
            lines.append("\(pad(role.rawValue, roleWidth))  \(count) files  \(patterns.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}
