import Foundation

/// The file-system questions this tool asks, behind a protocol so a test can
/// answer them from a fixture in memory rather than from a directory it had
/// to create first.
public protocol FileSystemProbing: Sendable {
    func directoryExists(at path: String) -> Bool
    func fileExists(at path: String) -> Bool
    func contents(of path: String) -> String?
}

public struct RealFileSystem: FileSystemProbing {
    public init() {}

    public func directoryExists(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    public func fileExists(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    public func contents(of path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }
}
