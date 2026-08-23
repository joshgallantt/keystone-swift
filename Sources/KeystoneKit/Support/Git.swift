import Foundation

/// Which files a run is answerable for, and which tree it reads them from.
///
/// These are two questions, and conflating them is how a tool ends up lying
/// about history. *Selection* narrows what gets reported — a branch, a commit,
/// the staging area. *Revision* decides which version of the code is read at
/// all. Reviewing a commit from last month against today's working tree would
/// report violations in code that commit never contained, so asking about a
/// commit changes both.
public struct CheckTarget: Sendable {
    public enum Selection: Sendable {
        /// Every file in the project.
        case everything
        /// What this branch changed, including work not yet committed.
        case working(since: String?)
        /// What is staged for the next commit.
        case staged
        /// What one commit touched.
        case commit(String)
        /// What a branch changed against the trunk.
        case branch(String)
    }

    public var selection: Selection
    /// The ref whose tree to read, or nil for the working tree.
    public var revision: String?

    public init(selection: Selection, revision: String? = nil) {
        self.selection = selection
        self.revision = revision
    }

    public static let everything = CheckTarget(selection: .everything)

    public var describesWholeProject: Bool {
        if case .everything = selection { return true }
        return false
    }
}

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

public enum GitError: Error, CustomStringConvertible {
    case notARepository(String)
    case noMergeBase
    case unknownRevision(String)
    case exportFailed(String)

    public var description: String {
        switch self {
        case .notARepository(let root):
            return "\(root) is not a git repository, so there is nothing to compare against."
        case .noMergeBase:
            return "Could not find where this branch left the trunk. In CI this usually means a shallow "
                + "clone — set `fetch-depth: 0` so the merge base exists."
        case .unknownRevision(let ref):
            return "`\(ref)` is not a revision this repository knows about."
        case .exportFailed(let ref):
            return "Could not read the project as it was at `\(ref)`."
        }
    }
}

public enum Git {
    public static func isRepository(_ root: String) -> Bool {
        Shell.run("git", ["rev-parse", "--git-dir"], in: root).status == 0
    }

    /// The top of the working tree, which is the project when no manifest
    /// names one.
    public static func repositoryRoot(_ from: String) -> String? {
        let result = Shell.run("git", ["rev-parse", "--show-toplevel"], in: from)
        guard result.status == 0 else { return nil }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : Paths.canonical(value)
    }

    public static func resolve(_ ref: String, root: String) -> String? {
        let result = Shell.run("git", ["rev-parse", "--verify", "--quiet", ref + "^{commit}"], in: root)
        guard result.status == 0 else { return nil }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// The files a target is answerable for, or nil when it is the whole
    /// project and no filtering applies.
    public static func files(for target: CheckTarget, root: String) throws -> Set<String>? {
        switch target.selection {
        case .everything:
            return nil

        case .working(let since):
            guard isRepository(root) else { throw GitError.notARepository(root) }
            guard let base = try since.map({ ref in
                guard let resolved = resolve(ref, root: root) else { throw GitError.unknownRevision(ref) }
                return resolved
            }) ?? mergeBase(root: root) else { throw GitError.noMergeBase }

            var files = Set(lines(Shell.run("git", ["diff", "--name-only", base], in: root).output))
            // Work that is not committed yet is still this branch's
            // responsibility, and is the state an agent is actually editing.
            files.formUnion(lines(Shell.run("git", ["ls-files", "--others", "--exclude-standard"], in: root).output))
            return files

        case .staged:
            guard isRepository(root) else { throw GitError.notARepository(root) }
            return Set(lines(Shell.run("git", ["diff", "--name-only", "--cached"], in: root).output))

        case .commit(let ref):
            guard isRepository(root) else { throw GitError.notARepository(root) }
            guard let resolved = resolve(ref, root: root) else { throw GitError.unknownRevision(ref) }
            // `--root` so the first commit in a repository reports its files
            // rather than nothing at all.
            let result = Shell.run(
                "git",
                ["diff-tree", "--no-commit-id", "--name-only", "-r", "--root", resolved],
                in: root
            )
            return Set(lines(result.output))

        case .branch(let name):
            guard isRepository(root) else { throw GitError.notARepository(root) }
            guard let head = resolve(name, root: root) else { throw GitError.unknownRevision(name) }
            guard let base = mergeBase(root: root, of: head) else { throw GitError.noMergeBase }
            return Set(lines(Shell.run("git", ["diff", "--name-only", base, head], in: root).output))
        }
    }

    /// Writes the project as it was at `ref` into a directory, so a past state
    /// can be checked without disturbing the working tree. `git archive` into a
    /// tarball rather than reading each blob: one process instead of one per
    /// file, which matters on a repository with a few thousand of them.
    public static func export(ref: String, root: String, to destination: String) throws {
        guard isRepository(root) else { throw GitError.notARepository(root) }
        guard let resolved = resolve(ref, root: root) else { throw GitError.unknownRevision(ref) }

        let archive = Paths.join(destination, ".keystone-export.tar")
        try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)

        let wrote = Shell.run("git", ["archive", "--format=tar", "--output=" + archive, resolved], in: root)
        guard wrote.status == 0 else { throw GitError.exportFailed(ref) }

        let extracted = Shell.run("tar", ["-xf", archive, "-C", destination], in: destination)
        try? FileManager.default.removeItem(atPath: archive)
        guard extracted.status == 0 else { throw GitError.exportFailed(ref) }
    }

    /// The point this branch left the trunk. Without it, branch scope would
    /// report every file the branch has ever seen rather than what it changed.
    public static func mergeBase(root: String, of head: String = "HEAD") -> String? {
        for candidate in trunkCandidates(root: root) {
            let result = Shell.run("git", ["merge-base", head, candidate], in: root)
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
