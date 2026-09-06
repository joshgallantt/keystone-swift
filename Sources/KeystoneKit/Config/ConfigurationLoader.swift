import Foundation

public enum ConfigurationError: Error, CustomStringConvertible {
    case missing(searchedFrom: String)
    case unreadable(path: String)
    case malformed(path: String, reason: String)

    public var description: String {
        switch self {
        case .missing(let from):
            return "No \(ConfigurationLoader.fileName) found in \(from) or any directory above it.\n"
                + "Run `keystone-swift init` to write one from what is already in this project."
        case .unreadable(let path):
            return "Could not read \(path)."
        case .malformed(let path, let reason):
            return "\(path) is not valid: \(reason)"
        }
    }
}

public enum ConfigurationLoader {
    public static let fileName = "keystone-swift.json"
    public static let baselineFileName = "keystone-swift.baseline.json"

    /// Walks upward, so the tool works from any directory inside a project —
    /// which matters because an agent's working directory is rarely the root.
    public static func discover(from directory: String) -> String? {
        var current = Paths.canonical(directory)
        while true {
            let candidate = Paths.join(current, fileName)
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
            let parent = Paths.directory(of: current)
            if parent.isEmpty || parent == current { return nil }
            current = parent
        }
    }

    /// A manifest states what it wants to change. Everything else stays as the
    /// preset had it.
    ///
    /// It used to replace the preset outright, because a manifest was only ever
    /// read instead of one. So a project that named one target for one layer —
    /// the override this tool documents for a layout it cannot read — lost the
    /// other six layers and every framework rule with them. On a 415-file app
    /// that turned 81 files unclassified and switched off most of the checking,
    /// silently. An override that costs a user everything they did not restate
    /// is not an override.
    public static func load(at path: String) throws -> Configuration {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw ConfigurationError.unreadable(path: path)
        }
        do {
            let base = try JSONEncoder().encode(Presets.cleanArchitecture(paths: [:]))
            let merged = ConfigurationLoader.overlay(manifest: data, onto: base) ?? data
            return try JSONDecoder().decode(Configuration.self, from: merged)
        } catch let error as DecodingError {
            throw ConfigurationError.malformed(path: path, reason: ConfigurationLoader.explain(error))
        }
    }

    /// A deep merge of one JSON object over another. An object merges key by
    /// key; anything else replaces. An array replaces rather than appends,
    /// because a project that restates a list means the list it wrote.
    static func overlay(manifest: Data, onto base: Data) -> Data? {
        guard let top = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any],
              let bottom = try? JSONSerialization.jsonObject(with: base) as? [String: Any]
        else { return nil }
        let merged = ConfigurationLoader.merge(top, over: bottom)
        return try? JSONSerialization.data(withJSONObject: merged)
    }

    static func merge(_ top: [String: Any], over bottom: [String: Any]) -> [String: Any] {
        var result = bottom
        for (key, value) in top {
            if let object = value as? [String: Any], let existing = result[key] as? [String: Any] {
                result[key] = ConfigurationLoader.merge(object, over: existing)
            } else {
                result[key] = value
            }
        }
        return result
    }

    public static func loadBaseline(root: String) -> Baseline? {
        let path = Paths.join(root, baselineFileName)
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(Baseline.self, from: data)
    }

    public static func write<T: Encodable>(_ value: T, to path: String) throws {
        let encoder = JSONEncoder()
        // Sorted keys so a regenerated file produces a reviewable diff rather
        // than a reshuffle.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        try data.write(to: URL(fileURLWithPath: path))
    }

    static func explain(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "missing `\(key.stringValue)` at \(path(context))"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "\(context.debugDescription) at \(path(context))"
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return "\(error)"
        }
    }

    static func path(_ context: DecodingError.Context) -> String {
        let parts = context.codingPath.map(\.stringValue)
        return parts.isEmpty ? "the top level" : parts.joined(separator: ".")
    }
}
