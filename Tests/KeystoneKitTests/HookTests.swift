import Foundation
import Testing
@testable import KeystoneKit

@Suite("The agent hook")
struct ClaudeHookTests {
    let hook = ClaudeHook()

    func payload(_ fields: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: fields), encoding: .utf8)!
    }

    @Test("a session opens with the rules already in context")
    func sessionStartHandsOverTheRules() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        let response = hook.respond(
            to: payload(["cwd": fixture.root, "hook_event_name": "SessionStart"]),
            defaultRoot: fixture.root
        )

        guard case .context(let text) = response else {
            Issue.record("expected context, got \(response)")
            return
        }
        #expect(text.contains("Architecture rules"))
        #expect(text.contains("May depend on"))
    }

    @Test("a write that breaks a boundary is refused, with the correction as the reason")
    func violatingWritesAreRefused() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        let response = hook.respond(
            to: payload([
                "cwd": fixture.root,
                "hook_event_name": "PreToolUse",
                "tool_name": "Write",
                "tool_input": [
                    "file_path": "Component/Catalog/Sources/Domain/Model/Basket.swift",
                    "content": "import SwiftUI\n\npublic struct Basket {}\n"
                ]
            ]),
            defaultRoot: fixture.root
        )

        guard case .deny(let reason) = response else {
            Issue.record("expected deny, got \(response)")
            return
        }
        #expect(reason.contains("SwiftUI"))
        // The refusal has to say what to do instead, or the next attempt is a guess.
        #expect(reason.contains("protocol"))
    }

    @Test("a write that respects the boundaries is allowed silently")
    func cleanWritesPassThrough() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        let response = hook.respond(
            to: payload([
                "cwd": fixture.root,
                "hook_event_name": "PreToolUse",
                "tool_name": "Write",
                "tool_input": [
                    "file_path": "Component/Catalog/Sources/Domain/Model/Basket.swift",
                    "content": "public struct Basket: Sendable {}\n"
                ]
            ]),
            defaultRoot: fixture.root
        )

        guard case .allow = response else {
            Issue.record("expected allow, got \(response)")
            return
        }
        #expect(response.json.isEmpty)
    }

    @Test("an edit is judged on what the file will say afterwards, not what it says now")
    func editsAreAppliedBeforeChecking() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        let response = hook.respond(
            to: payload([
                "cwd": fixture.root,
                "hook_event_name": "PreToolUse",
                "tool_name": "Edit",
                "tool_input": [
                    "file_path": "Component/Catalog/Sources/Domain/Model/Item.swift",
                    "old_string": "public struct Item",
                    "new_string": "import CatalogData\n\npublic struct Item"
                ]
            ]),
            defaultRoot: fixture.root
        )

        guard case .deny(let reason) = response else {
            Issue.record("expected deny, got \(response)")
            return
        }
        #expect(reason.contains("CatalogData"))
    }

    @Test("writing Swift through the shell is refused, since it would go around the check")
    func shellRedirectionIsRefused() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        func bash(_ command: String) -> HookResponse {
            hook.respond(
                to: payload([
                    "cwd": fixture.root,
                    "hook_event_name": "PreToolUse",
                    "tool_name": "Bash",
                    "tool_input": ["command": command]
                ]),
                defaultRoot: fixture.root
            )
        }

        for command in ["cat > Sources/Thing.swift", "echo x >> A.swift", "sed -i '' s/a/b/ A.swift"] {
            guard case .deny = bash(command) else {
                Issue.record("expected \(command) to be refused")
                return
            }
        }

        guard case .allow = bash("swift build") else {
            Issue.record("an ordinary command must not be refused")
            return
        }
    }

    @Test("a warning is surfaced without blocking the write")
    func warningsDoNotBlock() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        let response = hook.respond(
            to: payload([
                "cwd": fixture.root,
                "hook_event_name": "PreToolUse",
                "tool_name": "Write",
                "tool_input": [
                    "file_path": "Component/Catalog/Sources/Data/DefaultGauge.swift",
                    "content": "import Catalog\n\npublic struct DefaultGauge {\n    public init() {}\n}\n"
                ]
            ]),
            defaultRoot: fixture.root
        )

        guard case .note(let text) = response else {
            Issue.record("expected a note, got \(response)")
            return
        }
        #expect(text.contains("implementation"))
    }

    @Test("the turn cannot finish while the project is broken")
    func stopIsBlockedByNewViolations() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.prepend("Component/Catalog/Sources/Domain/Model/Item.swift", "import SwiftUI\n")

        let response = hook.respond(
            to: payload(["cwd": fixture.root, "hook_event_name": "Stop"]),
            defaultRoot: fixture.root
        )

        guard case .blockStop(let reason) = response else {
            Issue.record("expected the stop to be blocked, got \(response)")
            return
        }
        #expect(reason.contains("SwiftUI"))
    }

    @Test("debt already accepted does not make every turn unfinishable")
    func stopIgnoresBaselinedViolations() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try fixture.prepend("Component/Catalog/Sources/Domain/Model/Item.swift", "import SwiftUI\n")
        let result = try fixture.check()
        try ConfigurationLoader.write(
            Baseline.record(result.violations),
            to: Paths.join(fixture.root, ConfigurationLoader.baselineFileName)
        )

        let response = hook.respond(
            to: payload(["cwd": fixture.root, "hook_event_name": "Stop"]),
            defaultRoot: fixture.root
        )

        guard case .allow = response else {
            Issue.record("expected allow, got \(response)")
            return
        }
    }

    @Test("the project is found from the file being written, not from the working directory")
    func theProjectIsFoundFromTheFile() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        // An agent started above the project, or anywhere in a monorepo, has a
        // working directory that contains no manifest. Searching only upward
        // from there found nothing and allowed every write in silence — the
        // worst shape of failure this tool has, because a hook that permits
        // everything is indistinguishable from a codebase with no violations.
        let elsewhere = Paths.directory(of: fixture.root)

        let response = hook.respond(
            to: payload([
                "cwd": elsewhere,
                "hook_event_name": "PreToolUse",
                "tool_name": "Write",
                "tool_input": [
                    "file_path": Paths.join(fixture.root, "Component/Catalog/Sources/Domain/Model/Bad.swift"),
                    "content": "import SwiftUI\n\npublic struct Bad {}\n"
                ]
            ]),
            defaultRoot: elsewhere
        )

        guard case .deny(let reason) = response else {
            Issue.record("expected deny, got \(response)")
            return
        }
        #expect(reason.contains("SwiftUI"))
    }

    @Test("anything the hook cannot understand is allowed through")
    func doubtAllows() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        let cases = [
            "not json at all",
            payload(["cwd": fixture.root, "hook_event_name": "PreToolUse", "tool_name": "Write"]),
            payload([
                "cwd": fixture.root,
                "hook_event_name": "PreToolUse",
                "tool_name": "Write",
                "tool_input": ["file_path": "README.md", "content": "# hello"]
            ]),
            payload(["cwd": "/tmp/nowhere-at-all", "hook_event_name": "SessionStart"])
        ]

        for raw in cases {
            guard case .allow = hook.respond(to: raw, defaultRoot: fixture.root) else {
                Issue.record("expected allow for: \(raw.prefix(60))")
                return
            }
        }
    }

    @Test("a single pending file is not judged by rules that need the whole project")
    func wholeProjectRulesAreSkippedForOneFile() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        // Nothing claims this path, and in a project pass that is a warning.
        // Asked about one file, the tool has no basis for the claim and must
        // stay quiet rather than report a confident wrong answer.
        let result = try fixture.checkPending("Scratch/Loose.swift", "public struct Loose {}\n")
        #expect(!result.warningRules.contains("unclassified-files"))
    }
}

@Suite("Installing and removing")
struct InstallerTests {
    @Test("installing adds the hooks and leaves another tool's alone")
    func installPreservesForeignHooks() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        let settingsPath = ClaudeInstaller.settingsPath(root: fixture.root, user: false)
        try fixture.write(".claude/settings.json", """
        {
          "hooks": {
            "PreToolUse": [
              { "matcher": "Write", "hooks": [{ "type": "command", "command": "somebody-elses-tool" }] }
            ]
          },
          "model": "opus"
        }
        """)

        #expect(try ClaudeInstaller.install(root: fixture.root, user: false) == .added)
        #expect(try ClaudeInstaller.install(root: fixture.root, user: false) == .alreadyPresent)
        #expect(ClaudeInstaller.isInstalled(at: settingsPath))

        let settings = try ClaudeInstaller.read(settingsPath)
        #expect(settings["model"] as? String == "opus")

        #expect(try ClaudeInstaller.uninstall(root: fixture.root, user: false) == .removed)
        #expect(!ClaudeInstaller.isInstalled(at: settingsPath))

        // The other tool's hook, and the unrelated setting, must both survive.
        let after = try ClaudeInstaller.read(settingsPath)
        #expect(after["model"] as? String == "opus")
        let preToolUse = (after["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]]
        #expect(preToolUse?.count == 1)
    }

    @Test("removing something that was never installed changes nothing")
    func uninstallIsSafeWhenAbsent() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        #expect(try ClaudeInstaller.uninstall(root: fixture.root, user: false) == .notPresent)
    }

    @Test("the kiro and ci integrations write and remove their own files")
    func fileBasedIntegrationsRoundTrip() throws {
        let fixture = try Fixture.load("CleanApp")
        defer { fixture.destroy() }

        try KiroInstaller.install(root: fixture.root)
        #expect(FileManager.default.fileExists(atPath: Paths.join(fixture.root, KiroInstaller.hookPath)))
        #expect(try KiroInstaller.uninstall(root: fixture.root))
        #expect(!(try KiroInstaller.uninstall(root: fixture.root)))

        try CIInstaller.install(root: fixture.root)
        let workflow = try fixture.read(CIInstaller.workflowPath)
        #expect(workflow.contains("fetch-depth: 0"))
        #expect(try CIInstaller.uninstall(root: fixture.root))
    }
}
