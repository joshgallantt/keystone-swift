import Foundation

public enum AccessLevel: String, Sendable, Codable, Comparable {
    case `private`
    case `fileprivate`
    case `internal`
    case `package`
    case `public`
    case open

    private var rank: Int {
        switch self {
        case .private: return 0
        case .fileprivate: return 1
        case .internal: return 2
        case .package: return 3
        case .public: return 4
        case .open: return 5
        }
    }

    public static func < (lhs: AccessLevel, rhs: AccessLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

public struct ImportReference: Sendable, Hashable {
    public var module: String
    public var line: Int
    public var isTestable: Bool

    public init(module: String, line: Int, isTestable: Bool = false) {
        self.module = module
        self.line = line
        self.isTestable = isTestable
    }
}

public struct Declaration: Sendable, Hashable {
    public var name: String
    public var kind: DeclarationKind
    public var line: Int
    public var accessLevel: AccessLevel
    public var inheritedTypes: [String]
    public var isTopLevel: Bool
    public var isStatic: Bool

    public init(
        name: String,
        kind: DeclarationKind,
        line: Int,
        accessLevel: AccessLevel = .internal,
        inheritedTypes: [String] = [],
        isTopLevel: Bool = true,
        isStatic: Bool = false
    ) {
        self.name = name
        self.kind = kind
        self.line = line
        self.accessLevel = accessLevel
        self.inheritedTypes = inheritedTypes
        self.isTopLevel = isTopLevel
        self.isStatic = isStatic
    }

    /// Kinds that declare a type a boundary can be drawn around. A function or
    /// a variable is a member of something else's surface, not a surface.
    public var isNominalType: Bool {
        switch kind {
        case .protocol, .struct, .class, .actor, .enum, .typealias_: return true
        default: return false
        }
    }
}

public struct TypeReference: Sendable, Hashable {
    public var name: String
    public var line: Int

    public init(name: String, line: Int) {
        self.name = name
        self.line = line
    }
}

public struct CommentMatch: Sendable, Hashable {
    public var text: String
    public var line: Int

    public init(text: String, line: Int) {
        self.text = text
        self.line = line
    }
}

/// Everything one Swift file says that any rule cares about.
///
/// Extracted once per file and shared, because the expensive part is the parse
/// and the rules are cheap. It is also the seam that keeps rules honest: a rule
/// can only assert something this type can express, so a rule cannot quietly
/// start doing its own ad-hoc text matching.
public struct SourceFacts: Sendable {
    public var path: String
    public var imports: [ImportReference]
    public var declarations: [Declaration]
    public var extensions: [Declaration]
    public var typeReferences: [TypeReference]
    public var comments: [CommentMatch]

    public init(
        path: String,
        imports: [ImportReference] = [],
        declarations: [Declaration] = [],
        extensions: [Declaration] = [],
        typeReferences: [TypeReference] = [],
        comments: [CommentMatch] = []
    ) {
        self.path = path
        self.imports = imports
        self.declarations = declarations
        self.extensions = extensions
        self.typeReferences = typeReferences
        self.comments = comments
    }
}
