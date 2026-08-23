import Foundation

extension Commands {
    static func check(_ arguments: Arguments) -> Int32 {
        if let file = arguments.value("file") {
            return checkPendingFile(arguments, path: file)
        }

        guard let project = Commands.resolveProject(arguments) else { return ExitCode.undecidable }

        let target: CheckTarget
        do {
            target = try Commands.target(from: arguments)
        } catch {
            Output.error("\(error)")
            return ExitCode.undecidable
        }

        var root = project.root
        var configuration = project.configuration
        var exported: String?
        defer { exported.map { try? FileManager.default.removeItem(atPath: $0) } }

        // Reading a past tree means reading its configuration too, where it has
        // one. Judging old code by today's rules would report violations of
        // rules that did not exist when it was written.
        if let revision = target.revision {
            do {
                let destination = Paths.join(
                    NSTemporaryDirectory(),
                    "keystone-swift-\(UUID().uuidString)"
                )
                try Git.export(ref: revision, root: project.root, to: destination)
                exported = destination
                root = destination
                let carried = Paths.join(destination, ConfigurationLoader.fileName)
                if FileManager.default.fileExists(atPath: carried) {
                    configuration = try ConfigurationLoader.load(at: carried)
                }
            } catch {
                Output.error("\(error)")
                return ExitCode.undecidable
            }
        }

        let selected: Set<String>?
        do {
            selected = try Git.files(for: target, root: project.root)
        } catch {
            Output.error("\(error)")
            return ExitCode.undecidable
        }

        let result = Checker().checkProject(
            root: root,
            configuration: configuration,
            limitedTo: selected
        )

        let baseline = ConfigurationLoader.loadBaseline(root: root)
            ?? ConfigurationLoader.loadBaseline(root: project.root)
        let (fresh, accepted) = baseline?.partition(result.violations) ?? (result.violations, [])
        let reported = arguments.has("include-accepted") ? result.violations : fresh

        var shown = result
        shown.violations = reported

        if arguments.has("json") {
            Output.print(JSONReport.render(shown, accepted: accepted.count))
        } else {
            if let preamble = Commands.describe(target, selected: selected) {
                Output.print("")
                Output.print(preamble)
                Output.print("")
            }
            Output.write(
                Commands.report(colour: Commands.shouldColour(arguments), width: arguments.value("width"))
                    .render(
                        shown,
                        baselined: arguments.has("include-accepted") ? 0 : accepted.count,
                        scoped: selected != nil
                    )
            )
        }

        return shown.hasErrors ? ExitCode.violations : ExitCode.clean
    }

    /// Which tree, and which files of it, this run is answerable for.
    ///
    /// Asking about a commit or a branch reads that tree as well as narrowing
    /// to its files, unless `--at` says otherwise. Anything else reads the
    /// working tree, because that is what the person running it is looking at.
    static func target(from arguments: Arguments) throws -> CheckTarget {
        let at = arguments.value("at")

        if let commit = arguments.value("commit") {
            return CheckTarget(selection: .commit(commit), revision: at ?? commit)
        }
        if let branch = arguments.value("branch") {
            return CheckTarget(selection: .branch(branch), revision: at ?? branch)
        }
        if arguments.has("staged") {
            return CheckTarget(selection: .staged, revision: at)
        }
        if arguments.has("changed") || arguments.value("since") != nil {
            return CheckTarget(selection: .working(since: arguments.value("since")), revision: at)
        }
        return CheckTarget(selection: .everything, revision: at)
    }

    static func describe(_ target: CheckTarget, selected: Set<String>?) -> String? {
        let swiftFiles = selected.map { $0.filter { $0.hasSuffix(".swift") }.count }

        func scope(_ what: String) -> String {
            guard let swiftFiles else { return what }
            let noun = swiftFiles == 1 ? "Swift file" : "Swift files"
            return "\(what) — \(swiftFiles) \(noun)"
        }

        var line: String
        switch target.selection {
        case .everything:
            guard target.revision != nil else { return nil }
            line = "The whole project"
        case .working(let since):
            line = scope(since.map { "Changed since \($0)" } ?? "Changed on this branch, including uncommitted work")
        case .staged:
            line = scope("Staged for the next commit")
        case .commit(let ref):
            line = scope("Touched by commit \(ref)")
        case .branch(let name):
            line = scope("Changed on branch \(name)")
        }

        if let revision = target.revision {
            line += ", read as the project stood at \(revision)"
        }
        return line + "."
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
