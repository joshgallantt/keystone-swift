import Foundation

/// What the hook tells Claude Code to do.
public enum HookResponse: Sendable {
    /// Say nothing and get out of the way.
    case allow
    /// Refuse the write, with the correction as the reason.
    case deny(String)
    /// Let it through, but put something on the record.
    case note(String)
    /// Hand the agent the rules as the session opens.
    case context(String)
    /// Refuse to finish the turn, with what is still broken.
    case blockStop(String)

    public var json: String {
        switch self {
        case .allow:
            return ""
        case .deny(let reason):
            return encode([
                "hookSpecificOutput": [
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason
                ]
            ])
        case .note(let text):
            return encode(["systemMessage": text])
        case .context(let text):
            return encode([
                "hookSpecificOutput": [
                    "hookEventName": "SessionStart",
                    "additionalContext": text
                ]
            ])
        case .blockStop(let reason):
            return encode(["decision": "block", "reason": reason])
        }
    }

    private func encode(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
}

/// Answers one hook call.
///
/// The governing rule is that doubt allows. An unreadable payload, a file no
/// layer claims, a configuration that will not load — every one of those lets
/// the write through, because a tool that blocks on its own confusion is a tool
/// that gets uninstalled, and the command line and CI will still catch what
/// this missed. Refusals are reserved for things it is certain about.
public struct ClaudeHook: Sendable {
    private let fileSystem: FileSystemProbing

    public init(fileSystem: FileSystemProbing = RealFileSystem()) {
        self.fileSystem = fileSystem
    }

    /// Writing a source file through the shell would route around every rule
    /// here, so it is refused by name rather than left as a gap the agent can
    /// discover.
    static let shellWrite = try! NSRegularExpression(
        pattern: #"(^|[^>])>>?\s*\S+\.swift\b|(\btee\b|\bsed\s+-i\b|\bperl\s+-p?i\b)[^|]*\.swift\b"#
    )

    public func respond(to payload: String, defaultRoot: String) -> HookResponse {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .allow
        }

        let cwd = Paths.canonical((json["cwd"] as? String) ?? defaultRoot)
        let event = (json["hook_event_name"] as? String) ?? ""
        let input = (json["tool_input"] as? [String: Any]) ?? [:]

        // The project is the one containing the file being written, which is
        // not always the one the agent was started in. Searching only upward
        // from the working directory meant a session opened above a project —
        // or anywhere in a monorepo — found no manifest and allowed every
        // write in silence, which is the failure this tool exists to prevent
        // and the hardest one to notice, since a hook that permits everything
        // looks exactly like a codebase with no violations.
        let file = (input["file_path"] as? String).map {
            $0.hasPrefix("/") ? Paths.canonical($0) : Paths.absolute($0, in: cwd)
        }
        let origin = file.map(Paths.directory(of:)) ?? cwd

        guard let configurationPath = ConfigurationLoader.discover(from: origin)
                ?? ConfigurationLoader.discover(from: cwd),
              let configuration = try? ConfigurationLoader.load(at: configurationPath) else {
            return .allow
        }
        let root = Paths.directory(of: configurationPath)

        switch event {
        case "SessionStart":
            return .context(RulesDocument.render(configuration))
        case "Stop", "SubagentStop":
            return closeOut(root: root, configuration: configuration)
        default:
            return beforeTool(json: json, file: file, cwd: cwd, root: root, configuration: configuration)
        }
    }

    private func beforeTool(
        json: [String: Any],
        file: String?,
        cwd: String,
        root: String,
        configuration: Configuration
    ) -> HookResponse {
        let tool = (json["tool_name"] as? String) ?? ""
        let input = (json["tool_input"] as? [String: Any]) ?? [:]

        if tool == "Bash" {
            let command = (input["command"] as? String) ?? ""
            let range = NSRange(command.startIndex..<command.endIndex, in: command)
            guard ClaudeHook.shellWrite.firstMatch(in: command, options: [], range: range) != nil else {
                return .allow
            }
            // Only files inside the project. Writing a scratch file somewhere
            // else is nobody's business: the rule is that this project's source
            // must go through a checked tool, not that the agent may never
            // redirect into a `.swift` file anywhere on the machine.
            guard ClaudeHook.touchesProject(command: command, cwd: cwd, root: root) else { return .allow }
            return .deny(
                "This writes a Swift file through the shell, which goes around the architecture check.\n\n"
                + "Use the Write or Edit tool instead, so the change is checked before it lands."
            )
        }

        guard let absolute = file, absolute.hasSuffix(".swift") else { return .allow }
        guard let content = resolveContent(tool: tool, input: input, absolutePath: absolute) else {
            return .allow
        }

        let result = Checker(fileSystem: fileSystem).checkPending(
            root: root,
            configuration: configuration,
            pending: PendingFile(path: Paths.relative(absolute, to: root), content: content)
        )

        if !result.errors.isEmpty {
            return .deny(explain(result.errors))
        }
        if !result.warnings.isEmpty {
            return .note(explain(result.warnings))
        }
        return .allow
    }

    /// The whole-project pass, run when the agent thinks it has finished.
    ///
    /// Cycles, sibling coupling and unclassified files cannot be seen from a
    /// single write, so without this they would only ever be caught by CI —
    /// after the work was handed over. Only violations that are new against the
    /// baseline block, so an existing codebase's debt does not make every turn
    /// unfinishable.
    private func closeOut(root: String, configuration: Configuration) -> HookResponse {
        let result = Checker(fileSystem: fileSystem).checkProject(root: root, configuration: configuration)
        let baseline = ConfigurationLoader.loadBaseline(root: root)
        let fresh = baseline?.partition(result.violations).fresh ?? result.violations
        let errors = fresh.errors

        guard !errors.isEmpty else { return .allow }

        return .blockStop(
            "The architecture check found \(errors.count) "
            + "\(errors.count == 1 ? "violation" : "violations") introduced in this session.\n\n"
            + explain(errors)
            + "\n\nFix these before finishing. If a rule is wrong for this project, change "
            + "`\(ConfigurationLoader.fileName)` and say why — do not work around it."
        )
    }

    /// Whether a shell command names a Swift file inside the project.
    static func touchesProject(command: String, cwd: String, root: String) -> Bool {
        guard let paths = try? NSRegularExpression(pattern: #"\S+\.swift\b"#) else { return true }
        let range = NSRange(command.startIndex..<command.endIndex, in: command)

        for match in paths.matches(in: command, options: [], range: range) {
            guard let found = Range(match.range, in: command) else { continue }
            let raw = String(command[found]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
            let absolute = raw.hasPrefix("/") ? Paths.canonical(raw) : Paths.absolute(raw, in: cwd)
            // `relative` returns the input unchanged when it is outside.
            if Paths.relative(absolute, to: root) != absolute { return true }
        }
        return false
    }

    /// The content the file will have if this call is permitted.
    private func resolveContent(tool: String, input: [String: Any], absolutePath: String) -> String? {
        // Claude's Write tool has called this `content` and `file_text` across
        // versions; accepting both is cheaper than being wrong on one of them.
        if let content = input["content"] as? String { return content }
        if let content = input["file_text"] as? String { return content }

        guard let existing = fileSystem.contents(of: absolutePath) else { return nil }

        if let edits = input["edits"] as? [[String: Any]] {
            return apply(edits: edits, to: existing)
        }
        if let old = input["old_string"] as? String, let new = input["new_string"] as? String {
            let replaceAll = (input["replace_all"] as? Bool) ?? false
            return replaceAll
                ? existing.replacingOccurrences(of: old, with: new)
                : existing.replacingFirstOccurrence(of: old, with: new)
        }
        return nil
    }

    private func apply(edits: [[String: Any]], to content: String) -> String? {
        var result = content
        for edit in edits {
            guard let old = edit["old_string"] as? String,
                  let new = edit["new_string"] as? String else { return nil }
            let replaceAll = (edit["replace_all"] as? Bool) ?? false
            result = replaceAll
                ? result.replacingOccurrences(of: old, with: new)
                : result.replacingFirstOccurrence(of: old, with: new)
        }
        return result
    }

    /// One violation, phrased so the next attempt is the right one.
    func explain(_ violations: [Violation]) -> String {
        violations.map { violation in
            let where_ = violation.line.map { "\(violation.file):\($0)" } ?? violation.file
            return [
                "\(where_) — \(violation.summary)",
                violation.fix,
                violation.source
            ].compactMap { $0 }.joined(separator: "\n\n")
        }.joined(separator: "\n\n---\n\n")
    }
}

extension String {
    func replacingFirstOccurrence(of target: String, with replacement: String) -> String {
        guard let range = range(of: target) else { return self }
        return replacingCharacters(in: range, with: replacement)
    }
}
