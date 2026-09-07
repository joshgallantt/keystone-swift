import Foundation

/// Exit codes are part of the interface, because CI and agent hooks read them
/// rather than the text. `0` clean, `1` the architecture is broken, `2` the
/// tool could not decide — and `2` never blocks anything, because a tool that
/// fails closed on its own confusion gets uninstalled by the end of the day.
public enum ExitCode {
    public static let clean: Int32 = 0
    public static let violations: Int32 = 1
    public static let undecidable: Int32 = 2
}

public enum CommandLineInterface {
    public static func run(arguments: [String]) -> Int32 {
        let parsed = Arguments(arguments)

        // Read before the command, because these are the two things a person
        // types when they do not yet know what the commands are. They arrive as
        // flags, never as the command word, so a `case "--help"` below can never
        // be reached — and the empty command falls through to `check`, which is
        // how `keystone-swift --help` came to silently scan whatever directory
        // it was run from.
        if parsed.has("help") || parsed.has("h") { Output.print(Help.text); return ExitCode.clean }
        if parsed.has("version") || parsed.has("v") { Output.print(Version.current); return ExitCode.clean }

        // A misspelled option is not a request to check the whole tree. The
        // parser cannot tell `--projct` from a flag some command might read, so
        // the interface says which options exist and refuses the rest.
        if let unknown = parsed.unknownOptions.first {
            Output.error("Unknown option `--\(unknown)`.\n\n\(Help.text)")
            return ExitCode.undecidable
        }

        switch parsed.command {
        case "init": return Commands.initialise(parsed)
        case "check", "": return Commands.check(parsed)
        case "status": return Commands.status(parsed)
        case "baseline": return Commands.baseline(parsed)
        case "freeze": return Commands.freeze(parsed)
        case "graph": return Commands.graph(parsed)
        case "rules": return Commands.rules(parsed)
        case "hook": return Commands.hook(parsed)
        case "install": return Commands.install(parsed)
        case "uninstall": return Commands.uninstall(parsed)
        case "doctor": return Commands.doctor(parsed)
        case "version": Output.print(Version.current); return ExitCode.clean
        case "help": Output.print(Help.text); return ExitCode.clean
        default:
            Output.error("Unknown command `\(parsed.command)`.\n\n\(Help.text)")
            return ExitCode.undecidable
        }
    }
}

public enum Version {
    public static let current = "keystone-swift 0.1.0"
}

/// A deliberately small parser. The tool has no options that need more.
public struct Arguments: Sendable {
    public var command: String
    public var positional: [String]
    public var flags: Set<String>
    public var values: [String: String]

    /// Flags that take a value. Everything else is a switch, so an unknown
    /// flag can never silently swallow the argument after it.
    static let valued: Set<String> = [
        "root", "config", "since", "file", "width", "commit", "branch", "at", "reporter"
    ]

    /// Options that stand alone. Together with `valued` this is every option
    /// the tool has, which is what lets an unrecognised one be refused rather
    /// than ignored.
    static let switches: Set<String> = [
        "changed", "dry-run", "force", "include-accepted", "json", "list",
        "no-colour", "staged", "user", "help", "h", "version", "v",
        "roles", "refused"
    ]

    public init(_ arguments: [String]) {
        var command = ""
        var positional: [String] = []
        var flags: Set<String> = []
        var values: [String: String] = [:]

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            index += 1

            guard argument.hasPrefix("-") else {
                if command.isEmpty { command = argument } else { positional.append(argument) }
                continue
            }

            let stripped = argument.drop { $0 == "-" }
            if let equals = stripped.firstIndex(of: "=") {
                values[String(stripped[stripped.startIndex..<equals])] = String(stripped[stripped.index(after: equals)...])
                continue
            }

            let name = String(stripped)
            if Arguments.valued.contains(name), index < arguments.count {
                values[name] = arguments[index]
                index += 1
            } else {
                flags.insert(name)
            }
        }

        self.command = command
        self.positional = positional
        self.flags = flags
        self.values = values
    }

    public func has(_ flag: String) -> Bool { flags.contains(flag) }

    /// Options the tool does not recognise, in either form.
    public var unknownOptions: [String] {
        flags.union(values.keys)
            .subtracting(Arguments.switches)
            .subtracting(Arguments.valued)
            .sorted()
    }
    public func value(_ name: String) -> String? { values[name] }

    public var root: String {
        Paths.canonical(values["root"] ?? FileManager.default.currentDirectoryPath)
    }
}

public enum Output {
    public static func print(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    public static func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    public static func error(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    public static var isTerminal: Bool {
        isatty(FileHandle.standardOutput.fileDescriptor) == 1
    }
}

public enum Help {
    public static let text = """
    keystone-swift — architecture enforcement for Swift projects

    USAGE
      keystone-swift <command> [options]

    COMMANDS
      init              Read the project and write \(ConfigurationLoader.fileName) for review
      check             Check the project against the configuration          (default)
      status            Show which layers exist, what is unclassified, and the debt
      baseline          Record today's violations as accepted, so only new ones fail
      freeze            Narrow each layer's allow-list to the edges that exist today
      graph             Print the module graph as Mermaid, refused edges in red
      rules             Print the architecture as a document for an agent to read
      rules --list      Show every rule, its severity, and whether it runs
      hook              Answer an agent hook; reads the payload on stdin
      install <target>  Wire into claude, kiro or ci
      uninstall <target>  Take it back out again
      doctor            Report what is installed and whether the configuration loads

    WHAT TO CHECK
      (nothing)         The whole project
      --changed         What this branch changed, including uncommitted work
      --staged          What is staged for the next commit
      --branch <name>   What a branch changed against the trunk
      --commit <sha>    What one commit touched, read as the project stood then
      --since <ref>     Changes since a specific ref rather than the merge base
      --at <ref>        Read the project as it was at a ref, whatever the selection
      --file <path>     One file, with its content on stdin

    GRAPH OPTIONS
      (nothing)         Every module, grouped by layer
      --roles           Collapse to the layer graph, with a count on each edge
      --refused         Only the refused edges and the modules they touch

    FREEZE OPTIONS
      --dry-run         Say what would change without writing the manifest

    CHECK OPTIONS
      --json            Machine-readable output
      --reporter xcode  One line per violation, as Xcode parses it inline
      --reporter github GitHub Actions annotations, against the changed lines
      --include-accepted  Also report violations the baseline accepted
      --no-colour       Plain text even on a terminal

    GLOBAL OPTIONS
      --root <path>     Work on a project other than the current directory
      --config <path>   Use a configuration file elsewhere

    EXIT CODES
      0  clean          1  violations found          2  could not decide
    """
}
