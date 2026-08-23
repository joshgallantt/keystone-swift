import Foundation

extension Commands {
    /// Reads the agent's payload on stdin and answers on stdout.
    ///
    /// Always exits `0`. Claude Code reads the decision from the JSON, and a
    /// non-zero exit here would be read as the hook itself failing — which is a
    /// different thing from the write being refused, and gets reported to the
    /// user as a broken tool rather than a broken boundary.
    static func hook(_ arguments: Arguments) -> Int32 {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let payload = String(data: data, encoding: .utf8) ?? ""

        let response = ClaudeHook().respond(to: payload, defaultRoot: arguments.root)
        let json = response.json
        if !json.isEmpty { Output.write(json) }

        return ExitCode.clean
    }
}
