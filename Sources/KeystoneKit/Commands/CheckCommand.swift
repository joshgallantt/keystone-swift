import Foundation

extension Commands {
    static func check(_ arguments: Arguments) -> Int32 {
        if let file = arguments.value("file") {
            return checkPendingFile(arguments, path: file)
        }

        guard let project = Commands.resolveProject(arguments) else { return ExitCode.undecidable }

        var limit: Set<String>?
        if arguments.has("changed") || arguments.value("since") != nil {
            guard let changed = Git.changedFiles(root: project.root, since: arguments.value("since")) else {
                Output.error("Could not work out what this branch changed. Is \(project.root) a git repository "
                    + "with history? CI needs `fetch-depth: 0` for the merge base to exist.")
                return ExitCode.undecidable
            }
            limit = changed
        }

        let result = Checker().checkProject(
            root: project.root,
            configuration: project.configuration,
            limitedTo: limit
        )

        let baseline = ConfigurationLoader.loadBaseline(root: project.root)
        let (fresh, accepted) = baseline?.partition(result.violations) ?? (result.violations, [])
        let reported = arguments.has("include-accepted") ? result.violations : fresh

        var shown = result
        shown.violations = reported

        if arguments.has("json") {
            Output.print(JSONReport.render(shown, accepted: accepted.count))
        } else {
            Output.write(
                Commands.report(colour: Commands.shouldColour(arguments), width: arguments.value("width"))
                    .render(shown, baselined: arguments.has("include-accepted") ? 0 : accepted.count)
            )
        }

        return shown.hasErrors ? ExitCode.violations : ExitCode.clean
    }

    /// One file, with its content on standard input, so a caller can ask about
    /// a version of the file that does not exist on disk yet.
    static func checkPendingFile(_ arguments: Arguments, path: String) -> Int32 {
        guard let project = Commands.resolveProject(arguments) else { return ExitCode.undecidable }

        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let content = String(data: data, encoding: .utf8) else {
            Output.error("Could not read the file content from stdin as UTF-8.")
            return ExitCode.undecidable
        }

        let relative = path.hasPrefix("/") ? Paths.relative(path, to: project.root) : path
        let result = Checker().checkPending(
            root: project.root,
            configuration: project.configuration,
            pending: PendingFile(path: relative, content: content)
        )

        if arguments.has("json") {
            Output.print(JSONReport.render(result, accepted: 0))
        } else if !result.violations.isEmpty {
            Output.write(
                Commands.report(colour: Commands.shouldColour(arguments), width: arguments.value("width"))
                    .render(result)
            )
        }

        return result.hasErrors ? ExitCode.violations : ExitCode.clean
    }
}
