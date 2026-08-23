import Foundation

/// Says where misplaced code should go, in this repository's own vocabulary.
///
/// The point of the tool is not to inventory what is wrong. It is to move an
/// existing app toward a shape it does not yet have, one refusal at a time —
/// and that only works if every refusal ends with a destination. "ViewModels
/// belong in presentation" teaches nothing to someone who does not already
/// know the layout; "move this to `UI/BagUI/Sources/UI/`" can be acted on
/// without understanding the architecture at all, and understanding follows
/// from having done it a few times.
public struct DestinationAdvisor: Sendable {
    private let configuration: Configuration

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    /// A concrete directory for `role`, aligned to the wildcards of the path
    /// the file is in now. Falls back to the plain pattern when the two layers
    /// are not laid out alike, which is still better than naming no place.
    public func directory(for role: Role, movingFrom path: String) -> String? {
        guard let target = configuration.definition(for: role)?.paths.first else { return nil }

        // Try to carry across whatever the current location already tells us —
        // usually the component or feature name, which is the part a generic
        // pattern cannot know.
        for (_, definition) in configuration.orderedRoles {
            for pattern in definition.paths {
                guard let captures = Glob(pattern).captures(path) else { continue }
                let filled = Glob.fill(target, with: captures)
                if !filled.contains("*") { return DestinationAdvisor.tidy(filled) }
            }
        }

        return DestinationAdvisor.tidy(target)
    }

    /// A sentence naming the destination, or nil when the configuration does
    /// not describe one. Rules append their own reasoning to this.
    public func advice(for role: Role, movingFrom path: String) -> String? {
        guard let directory = directory(for: role, movingFrom: path) else { return nil }
        let name = Paths.lastComponent(of: path)
        return "Move it to \(directory)\(name)."
    }

    /// Strips the trailing `**` a path pattern ends in so the result reads as
    /// a directory rather than as a pattern.
    static func tidy(_ pattern: String) -> String {
        var value = pattern
        while value.hasSuffix("*") || value.hasSuffix("/") {
            value = String(value.dropLast())
        }
        return value.isEmpty ? "" : value + "/"
    }
}
