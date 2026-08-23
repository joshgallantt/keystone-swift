import Foundation

public enum Shell {
    public struct Result: Sendable {
        public var status: Int32
        public var output: String
    }

    @discardableResult
    public static func run(_ executable: String, _ arguments: [String], in directory: String) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return Result(status: -1, output: "")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(
            status: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }
}

/// Which files this branch touched.
///
/// Branch scope is what makes the tool adoptable on a codebase that predates
/// it: a pull request is judged on what it changed, not on what it inherited.
public enum Git {
    public static func isRepository(_ root: String) -> Bool {
        Shell.run("git", ["rev-parse", "--git-dir"], in: root).status == 0
    }

    public static func changedFiles(root: String, since explicit: String?) -> Set<String>? {
        guard isRepository(root) else { return nil }
        guard let base = explicit ?? mergeBase(root: root) else { return nil }

        var files: Set<String> = []
        let diff = Shell.run("git", ["diff", "--name-only", base], in: root)
        guard diff.status == 0 else { return nil }
        files.formUnion(lines(diff.output))

        // Work that is not committed yet is still work this branch is
        // responsible for, and is the state an agent is actually editing.
        let untracked = Shell.run("git", ["ls-files", "--others", "--exclude-standard"], in: root)
        if untracked.status == 0 { files.formUnion(lines(untracked.output)) }

        return files
    }

    /// The point this branch left the trunk. Without it, branch scope would
    /// report every file the branch has ever seen rather than what it changed.
    static func mergeBase(root: String) -> String? {
        for candidate in trunkCandidates(root: root) {
            let result = Shell.run("git", ["merge-base", "HEAD", candidate], in: root)
            if result.status == 0 {
                let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    static func trunkCandidates(root: String) -> [String] {
        var candidates: [String] = []
        let head = Shell.run("git", ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], in: root)
        if head.status == 0 {
            let value = head.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { candidates.append(value) }
        }
        candidates.append(contentsOf: ["origin/main", "origin/master", "main", "master"])
        return candidates
    }

    static func lines(_ text: String) -> [String] {
        text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}
