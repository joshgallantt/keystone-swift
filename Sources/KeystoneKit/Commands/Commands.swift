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
            Output.error(ConfigurationError.missing(searchedFrom: arguments.root).description)
            return nil
        }

        do {
            let configuration = try ConfigurationLoader.load(at: path)
            let root = explicit != nil ? arguments.root : Paths.directory(of: path)
            return (root.isEmpty ? arguments.root : root, configuration)
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
