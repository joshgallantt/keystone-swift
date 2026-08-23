import Foundation

/// One file per command, so a change to how `init` behaves cannot disturb how
/// `check` behaves. The shared plumbing is here and nowhere else.
public enum Commands {
    /// The project root is the directory holding the configuration, never the
    /// working directory. An agent runs from wherever it happens to be, and a
    /// tool whose answers depend on that is not deterministic in the way that
    /// matters.
    static func resolveProject(_ arguments: Arguments) -> (root: String, configuration: Configuration)? {
        let explicit = arguments.value("config")
        guard let path = explicit ?? ConfigurationLoader.discover(from: arguments.root) else {
            // No manifest is the ordinary case, not an error. Layers are read
            // from the repository itself, and a manifest exists only to state
            // what evidence cannot: a severity, a rule switched off, a layout
            // too unusual to read.
            let root = Git.repositoryRoot(arguments.root) ?? arguments.root
            return (root, Presets.cleanArchitecture(paths: [:]))
        }

        do {
            let configuration = try ConfigurationLoader.load(at: path)
            let root = explicit != nil ? arguments.root : Paths.directory(of: path)
            return (Paths.canonical(root.isEmpty ? arguments.root : root), configuration)
        } catch {
            Output.error("\(error)")
            return nil
        }
    }

    static func report(colour: Bool, width: String?) -> TextReport {
        TextReport(width: Int(width ?? "") ?? 92, colour: colour)
    }

    static func shouldColour(_ arguments: Arguments) -> Bool {
        !arguments.has("no-colour") && !arguments.has("json") && Output.isTerminal
    }
}
