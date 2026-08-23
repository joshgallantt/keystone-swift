import Foundation

/// The gate that catches whatever the write path missed.
///
/// The hooks are the fast, forgiving layer: they allow anything they cannot
/// decide. This is the slow, complete one — it sees the whole project, has no
/// agent waiting on it, and is the only place a violation cannot be shrugged
/// off. Both are needed, and for different reasons.
public enum CIInstaller {
    public static let workflowPath = ".github/workflows/architecture.yml"
    public static let repository = "joshgallantt/keystone-swift"
    public static let tokenSecret = "KEYSTONE_SWIFT_TOKEN"

    public static func install(root: String) throws {
        let path = Paths.join(root, workflowPath)
        try FileManager.default.createDirectory(
            atPath: Paths.directory(of: path),
            withIntermediateDirectories: true
        )
        try workflow.write(toFile: path, atomically: true, encoding: .utf8)
    }

    public static func uninstall(root: String) throws -> Bool {
        let path = Paths.join(root, workflowPath)
        guard FileManager.default.fileExists(atPath: path) else { return false }
        try FileManager.default.removeItem(atPath: path)
        return true
    }

    public static func describe(root: String) -> String {
        FileManager.default.fileExists(atPath: Paths.join(root, workflowPath))
            ? "workflow present at \(workflowPath)"
            : "not installed — `keystone-swift install ci`"
    }

    static let workflow = """
    name: architecture

    on:
      pull_request:
      push:
        branches: [main, master]

    jobs:
      keystone-swift:
        runs-on: ubuntu-latest
        # Static analysis only — the project is never built, so the toolchain
        # here only has to compile keystone-swift itself. Swap this for
        # `runs-on: macos-latest` and drop the container if you would rather
        # use Xcode's Swift.
        container: swift:6.2

        steps:
          - uses: actions/checkout@v4
            with:
              # Required: without full history there is no merge base, so
              # `--changed` cannot tell new violations from inherited ones.
              fetch-depth: 0

          - name: Check out keystone-swift
            uses: actions/checkout@v4
            with:
              repository: \(repository)
              path: .keystone-swift
              # A fine-grained PAT with read access to the tool's repository,
              # stored as a repository secret. Not needed once the tool is public.
              token: ${{ secrets.\(tokenSecret) }}

          - name: Cache the build
            uses: actions/cache@v4
            with:
              path: .keystone-swift/.build
              key: keystone-swift-${{ runner.os }}-${{ hashFiles('.keystone-swift/Package.resolved') }}
              restore-keys: keystone-swift-${{ runner.os }}-

          - name: Build keystone-swift
            run: swift build -c release --package-path .keystone-swift

          - name: Check the architecture
            # Violations already recorded in keystone-swift.baseline.json are
            # not reported, so this fails only on something new. Delete the
            # baseline once the project is clean and this becomes absolute.
            run: .keystone-swift/.build/release/keystone-swift check --root .

    """
}
