import Foundation

/// Wires the tool into Kiro.
///
/// Kiro's hooks fire after a file is saved, not before it is written, so this
/// integration reports rather than prevents. That is stated here and in the
/// generated file rather than glossed over: a team that believes writes are
/// being blocked when they are only being reported will draw the wrong
/// conclusion from a quiet log.
public enum KiroInstaller {
    public static let hookPath = ".kiro/hooks/keystone-swift.kiro.hook"
    public static let steeringPath = ".kiro/steering/keystone-swift.md"

    public static func install(root: String) throws {
        try write(hook, to: Paths.join(root, hookPath))
        try write(steering, to: Paths.join(root, steeringPath))
    }

    public static func uninstall(root: String) throws -> Bool {
        var removed = false
        for path in [hookPath, steeringPath] {
            let absolute = Paths.join(root, path)
            if FileManager.default.fileExists(atPath: absolute) {
                try FileManager.default.removeItem(atPath: absolute)
                removed = true
            }
        }
        return removed
    }

    public static func describe(root: String) -> String {
        FileManager.default.fileExists(atPath: Paths.join(root, hookPath))
            ? "installed in this project"
            : "not installed — `keystone-swift install kiro`"
    }

    static let hook = """
    {
      "enabled": true,
      "name": "keystone-swift",
      "description": "Check the architecture after a Swift file is saved. Kiro hooks run after the write, so this reports a violation rather than preventing it — the pre-write refusal is only available in agents with a pre-tool hook.",
      "version": "1",
      "when": {
        "type": "fileEdited",
        "patterns": ["**/*.swift", "**/Package.swift"]
      },
      "then": {
        "type": "askAgent",
        "prompt": "Run `keystone-swift check --changed`. If it reports violations, fix them now: each one names the layer that was crossed, what that layer may reach instead, and where the code should go. Move the code rather than working around the rule. If a rule is genuinely wrong for this project, change keystone-swift.json and say why."
      }
    }

    """

    /// Points at the tool rather than restating it. A steering file is a copy,
    /// and a copy of the rules drifts from the file the checker reads while
    /// still sounding authoritative — so this one holds the instruction to go
    /// and read the real thing.
    static let steering = """
    ---
    inclusion: always
    ---

    # Architecture

    This project's architecture is enforced mechanically. The rules live in
    `keystone-swift.json` and nowhere else.

    Before writing Swift here, run:

    ```
    keystone-swift rules
    ```

    That prints the layers, what each may depend on, which frameworks each refuses, and where each
    kind of declaration belongs — generated from the manifest a moment before you read it.

    Before handing work back, run:

    ```
    keystone-swift check
    ```

    Every violation names the layer that was crossed, what it may reach instead, and where the code
    should go. Move the code rather than working around the rule: an import deleted while the
    dependency stays is a worse state than the one you started in.

    This file deliberately does not restate the rules. A second copy would drift from the one the
    checker actually applies, and would still read as authoritative while being wrong.

    """

    static func write(_ contents: String, to path: String) throws {
        try FileManager.default.createDirectory(
            atPath: Paths.directory(of: path),
            withIntermediateDirectories: true
        )
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
