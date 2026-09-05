import Foundation

/// Where every type in the repository is declared, and therefore which layer
/// owns it.
///
/// This is the piece that lets a rule be written without naming a project's
/// types. "A screen may not extend a domain type" needs no list of domain
/// types if the index can be asked which layer declared `Order`. The same
/// question answers "this presentation file mentions something only the data
/// layer knows about" in a codebase the author has never seen.
public struct SymbolIndex: Sendable {
    public struct Entry: Sendable, Hashable {
        public var name: String
        public var kind: DeclarationKind
        public var file: String
        public var line: Int
        public var module: String?
        public var role: Role?
    }

    private let entries: [String: [Entry]]

    public init(entries: [Entry]) {
        var table: [String: [Entry]] = [:]
        for entry in entries {
            table[entry.name, default: []].append(entry)
        }
        // Sorted so that the entry a report points at is the same one every
        // time, whatever order the file system handed the files over in.
        for key in table.keys {
            table[key]?.sort { $0.file == $1.file ? $0.line < $1.line : $0.file < $1.file }
        }
        self.entries = table
    }

    public func declarations(of name: String) -> [Entry] {
        entries[name] ?? []
    }

    /// True when two modules declare the same name. Swift allows it, and any
    /// rule reading an unqualified reference has no way to tell which one was
    /// meant — so ambiguity is reported as such and the rule declines rather
    /// than picking one and being right half the time.
    public func isAmbiguous(_ name: String) -> Bool {
        declaringScopes(of: name).count > 1
    }

    /// The role that declared a name, when exactly one layer did.
    public func declaringRole(of name: String) -> Role? {
        let found = declarations(of: name)
        guard !found.isEmpty else { return nil }
        let roles = Set(found.compactMap(\.role))
        guard roles.count == 1 else { return nil }
        return roles.first
    }

    public func declaringModules(of name: String) -> Set<String> {
        Set(declarations(of: name).compactMap(\.module))
    }

    /// The declaring modules including "none", so that a project with no
    /// modules at all is still comparable. An app that is one Xcode target
    /// with folders has no module boundaries to speak of, and dropping the
    /// absent ones here would have quietly exempted exactly the codebases this
    /// tool exists to help.
    public func declaringScopes(of name: String) -> Set<String?> {
        Set(declarations(of: name).map(\.module))
    }

    public static func build(
        files: [AnalyzedFile],
        graph: ProjectGraph
    ) -> SymbolIndex {
        var entries: [Entry] = []
        for file in files {
            // Top-level only. A nested `enum Button` inside one view is not the
            // same symbol as another module's `Button`, and indexing it made every
            // reference to the common name resolve to whichever file happened to
            // declare a nested one — which is where `type-reference-boundary`'s
            // shadow findings came from.
            for declaration in file.facts.declarations
            where declaration.isNominalType && declaration.isTopLevel {
                entries.append(
                    Entry(
                        name: declaration.name,
                        kind: declaration.kind,
                        file: file.path,
                        line: declaration.line,
                        module: file.module?.name,
                        role: file.role
                    )
                )
            }
        }
        return SymbolIndex(entries: entries)
    }
}
