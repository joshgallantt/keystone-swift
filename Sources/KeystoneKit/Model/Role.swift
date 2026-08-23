import Foundation

/// What a piece of code is *for*, independent of what it is called.
///
/// Roles are an open set. The built-in names cover the layering nearly every
/// iOS codebase already has, but a project that genuinely has more layers
/// declares them in its configuration and the dependency matrix follows,
/// because no rule in this tool is written against a specific role name.
public struct Role: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static let domain = Role("domain")
    public static let data = Role("data")
    public static let presentation = Role("presentation")
    public static let composition = Role("composition")
    public static let library = Role("library")
    public static let tests = Role("tests")

    /// The order roles are printed in, so two runs never disagree about
    /// which violation comes first.
    public static let conventionalOrder: [Role] = [
        .domain, .data, .presentation, .composition, .library, .tests
    ]
}

extension Role: Codable {
    public init(from decoder: Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension Role: Comparable {
    public static func < (lhs: Role, rhs: Role) -> Bool {
        let order = Role.conventionalOrder
        let left = order.firstIndex(of: lhs) ?? order.count
        let right = order.firstIndex(of: rhs) ?? order.count
        return left == right ? lhs.rawValue < rhs.rawValue : left < right
    }
}

/// How a role treats its own kind. A domain may build on another domain —
/// that is a business rule composing a business rule. Two feature screens
/// depending on each other is a different thing wearing the same shape, so
/// the two cases are told apart by where the code lives rather than lumped
/// together under one permission.
public enum SameRolePolicy: String, Codable, Sendable {
    /// Any target of this role may depend on any other of the same role.
    case allow
    /// Permitted inside one package, refused between packages.
    case denyAcrossPackages
    /// Never permitted.
    case deny
}
