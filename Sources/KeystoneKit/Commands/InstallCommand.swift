import Foundation

extension Commands {
    static func install(_ arguments: Arguments) -> Int32 {
        guard let target = arguments.positional.first else {
            Output.error("Which one? `keystone-swift install claude|kiro|ci [--user]`")
            return ExitCode.undecidable
        }

        let root = arguments.root
        let user = arguments.has("user")

        do {
            switch target {
            case "claude":
                let outcome = try ClaudeInstaller.install(root: root, user: user)
                let where_ = Paths.relative(ClaudeInstaller.settingsPath(root: root, user: user), to: root)
                if outcome == .alreadyPresent {
                    Output.print("Already wired into \(where_). Nothing changed.")
                } else {
                    Output.print("""
                    Wired into \(where_).

                      SessionStart   hands the agent the rules before it writes anything
                      PreToolUse     refuses a Write or Edit that breaks a boundary, with the correction
                      Stop           checks the whole project before the turn is allowed to finish

                    Reading a rule costs nothing; being refused costs a write and a retry. That is why the
                    session hook is there as well as the gate.
                    """)
                }

            case "kiro":
                try KiroInstaller.install(root: root)
                Output.print("""
                Wrote \(KiroInstaller.hookPath) and \(KiroInstaller.steeringPath).

                Kiro's hooks run after a file is saved, so this reports a violation rather than
                preventing it. The steering file tells the agent to read the rules first, which is
                the cheaper of the two.
                """)

            case "ci":
                try CIInstaller.install(root: root)
                Output.print("""
                Wrote \(CIInstaller.workflowPath).

                Add a repository secret named \(CIInstaller.tokenSecret) — a fine-grained token with read
                access to \(CIInstaller.repository) — so the runner can fetch the tool.

                The workflow reports only violations that are new against keystone-swift.baseline.json,
                so it can be turned on today without failing on inherited debt.
                """)

            default:
                Output.error("Unknown target `\(target)`. Choose claude, kiro or ci.")
                return ExitCode.undecidable
            }
        } catch {
            Output.error("\(error)")
            return ExitCode.undecidable
        }

        return ExitCode.clean
    }

    static func uninstall(_ arguments: Arguments) -> Int32 {
        guard let target = arguments.positional.first else {
            Output.error("Which one? `keystone-swift uninstall claude|kiro|ci|all [--user]`")
            return ExitCode.undecidable
        }

        let root = arguments.root
        let user = arguments.has("user")
        let targets = target == "all" ? ["claude", "kiro", "ci"] : [target]
        var touched: [String] = []

        do {
            for one in targets {
                switch one {
                case "claude":
                    if try ClaudeInstaller.uninstall(root: root, user: user) == .removed {
                        touched.append("Claude Code hooks")
                    }
                    // Removing from a project should not silently leave the
                    // user-wide install in place without saying so.
                    if !user, target == "all", try ClaudeInstaller.uninstall(root: root, user: true) == .removed {
                        touched.append("Claude Code hooks (all projects)")
                    }
                case "kiro":
                    if try KiroInstaller.uninstall(root: root) { touched.append("Kiro hook and steering file") }
                case "ci":
                    if try CIInstaller.uninstall(root: root) { touched.append(CIInstaller.workflowPath) }
                default:
                    Output.error("Unknown target `\(one)`. Choose claude, kiro, ci or all.")
                    return ExitCode.undecidable
                }
            }
        } catch {
            Output.error("\(error)")
            return ExitCode.undecidable
        }

        if touched.isEmpty {
            Output.print("Nothing to remove.")
        } else {
            Output.print("Removed: \(touched.joined(separator: ", ")).")
            Output.print("\(ConfigurationLoader.fileName) and \(ConfigurationLoader.baselineFileName) are left "
                + "alone — they describe your project, not this tool.")
        }

        return ExitCode.clean
    }
}
