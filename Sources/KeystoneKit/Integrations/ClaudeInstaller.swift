import Foundation

/// Wires the tool into Claude Code, and takes it back out again.
///
/// Every entry carries the same command, which is also the marker used to
/// remove it. That means installing is idempotent, uninstalling takes back
/// exactly what was added, and hooks belonging to other tools in the same
/// settings file are left untouched — a tool that is awkward to remove is one
/// people avoid installing.
public enum ClaudeInstaller {
    public static let marker = "keystone-swift hook"

    struct Entry {
        var event: String
        var matcher: String?
        var statusMessage: String
    }

    static let entries: [Entry] = [
        Entry(
            event: "SessionStart",
            matcher: "startup|resume|clear|compact",
            statusMessage: "Loading architecture rules..."
        ),
        Entry(
            event: "PreToolUse",
            matcher: "Write|Edit|MultiEdit|Bash",
            statusMessage: "Checking architecture..."
        ),
        // The whole-project pass. Cycles and sibling coupling are invisible
        // from a single write, so without this they would first be seen by CI,
        // after the work was handed over as finished.
        Entry(
            event: "Stop",
            matcher: nil,
            statusMessage: "Checking the architecture as a whole..."
        )
    ]

    public static func settingsPath(root: String, user: Bool) -> String {
        user
            ? Paths.join(NSHomeDirectory(), ".claude", "settings.json")
            : Paths.join(root, ".claude", "settings.json")
    }

    public enum Outcome: Sendable {
        case added
        case alreadyPresent
        case removed
        case notPresent
    }

    public static func install(root: String, user: Bool) throws -> Outcome {
        let path = settingsPath(root: root, user: user)
        var settings = try read(path)
        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]
        var changed = false

        for entry in entries {
            var matchers = (hooks[entry.event] as? [[String: Any]]) ?? []
            let present = matchers.contains { matcher in
                let nested = (matcher["hooks"] as? [[String: Any]]) ?? []
                return nested.contains { ($0["command"] as? String)?.contains(marker) == true }
            }
            if present { continue }

            var entryValue: [String: Any] = [
                "hooks": [[
                    "type": "command",
                    "command": marker,
                    "statusMessage": entry.statusMessage
                ]]
            ]
            if let matcher = entry.matcher { entryValue["matcher"] = matcher }

            matchers.append(entryValue)
            hooks[entry.event] = matchers
            changed = true
        }

        guard changed else { return .alreadyPresent }
        settings["hooks"] = hooks
        try write(settings, to: path)
        return .added
    }

    public static func uninstall(root: String, user: Bool) throws -> Outcome {
        let path = settingsPath(root: root, user: user)
        guard FileManager.default.fileExists(atPath: path) else { return .notPresent }

        var settings = try read(path)
        guard var hooks = settings["hooks"] as? [String: Any] else { return .notPresent }
        var changed = false

        for (event, value) in hooks {
            guard let matchers = value as? [[String: Any]] else { continue }
            let kept = matchers.compactMap { matcher -> [String: Any]? in
                let nested = (matcher["hooks"] as? [[String: Any]]) ?? []
                let remaining = nested.filter { ($0["command"] as? String)?.contains(marker) != true }
                if remaining.count == nested.count { return matcher }
                changed = true
                guard !remaining.isEmpty else { return nil }
                var copy = matcher
                copy["hooks"] = remaining
                return copy
            }
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }

        guard changed else { return .notPresent }
        if hooks.isEmpty { settings.removeValue(forKey: "hooks") } else { settings["hooks"] = hooks }
        try write(settings, to: path)
        return .removed
    }

    public static func describe(root: String) -> String {
        let project = isInstalled(at: settingsPath(root: root, user: false))
        let user = isInstalled(at: settingsPath(root: root, user: true))
        switch (project, user) {
        case (true, true): return "installed in this project and for all projects"
        case (true, false): return "installed in this project"
        case (false, true): return "installed for all projects"
        case (false, false): return "not installed — `keystone-swift install claude`"
        }
    }

    static func isInstalled(at path: String) -> Bool {
        guard let settings = try? read(path),
              let hooks = settings["hooks"] as? [String: Any] else { return false }
        for value in hooks.values {
            guard let matchers = value as? [[String: Any]] else { continue }
            for matcher in matchers {
                let nested = (matcher["hooks"] as? [[String: Any]]) ?? []
                if nested.contains(where: { ($0["command"] as? String)?.contains(marker) == true }) {
                    return true
                }
            }
        }
        return false
    }

    /// Read as untyped JSON on purpose: settings this tool knows nothing about
    /// must survive being rewritten by it.
    static func read(_ path: String) throws -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: path) else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.unreadable(path)
        }
        return object
    }

    static func write(_ settings: [String: Any], to path: String) throws {
        try FileManager.default.createDirectory(
            atPath: Paths.directory(of: path),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try (String(data: data, encoding: .utf8)! + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}

public enum InstallError: Error, CustomStringConvertible {
    case unreadable(String)

    public var description: String {
        switch self {
        case .unreadable(let path):
            return "\(path) is not valid JSON. Fix or move it before installing, so nothing in it is lost."
        }
    }
}
