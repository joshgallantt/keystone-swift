import Foundation
@testable import KeystoneKit

/// A throwaway copy of a fixture project, so a test can break it on purpose.
///
/// Mutation is the only honest way to test a checker. A suite that runs the
/// clean fixture and asserts silence proves nothing about whether the rules do
/// anything at all — every rule passes if every rule is switched off. Each test
/// here introduces exactly one fault and names the rule that must notice.
struct Fixture {
    let root: String

    static func load(_ name: String) throws -> Fixture {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)

        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keystone-swift-tests")
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: source, to: destination)
        return Fixture(root: Paths.canonical(destination.path))
    }

    func destroy() {
        try? FileManager.default.removeItem(atPath: root)
    }

    // MARK: - Breaking things

    func write(_ relative: String, _ contents: String) throws {
        let path = Paths.absolute(relative, in: root)
        try FileManager.default.createDirectory(
            atPath: Paths.directory(of: path),
            withIntermediateDirectories: true
        )
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func read(_ relative: String) throws -> String {
        try String(contentsOfFile: Paths.absolute(relative, in: root), encoding: .utf8)
    }

    func prepend(_ relative: String, _ contents: String) throws {
        try write(relative, contents + (try read(relative)))
    }

    func append(_ relative: String, _ contents: String) throws {
        try write(relative, (try read(relative)) + contents)
    }

    struct AnchorMissing: Error, CustomStringConvertible {
        var file: String
        var anchor: String
        var description: String { "\(file) no longer contains the anchor:\n\(anchor)" }
    }

    /// Throws rather than trapping. A fixture that has drifted should fail one
    /// test, not take the whole run down with it.
    func replace(_ relative: String, _ old: String, with new: String) throws {
        let existing = try read(relative)
        guard existing.contains(old) else { throw AnchorMissing(file: relative, anchor: old) }
        try write(relative, existing.replacingOccurrences(of: old, with: new))
    }

    // MARK: - Asking

    func configuration() throws -> Configuration {
        try ConfigurationLoader.load(at: Paths.join(root, ConfigurationLoader.fileName))
    }

    func check() throws -> CheckResult {
        Checker().checkProject(root: root, configuration: try configuration())
    }

    func checkPending(_ relative: String, _ contents: String) throws -> CheckResult {
        Checker().checkPending(
            root: root,
            configuration: try configuration(),
            pending: PendingFile(path: relative, content: contents)
        )
    }
}

extension CheckResult {
    /// The rules that produced an error, which is what a mutation test asserts
    /// on — the count matters less than which rule woke up.
    var erroringRules: Set<String> {
        Set(errors.map(\.rule))
    }

    var warningRules: Set<String> {
        Set(warnings.map(\.rule))
    }
}
