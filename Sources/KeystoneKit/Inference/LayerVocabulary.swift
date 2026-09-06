import Foundation

/// The words Swift codebases already use for their layers.
///
/// Inference reads directory names before anything else, because a directory
/// name is the one place a team has already written down what it thinks the
/// code is.
///
/// The list is short on purpose, and the omissions are the design. `Repository`
/// is absent because `Domain/Repository` holds contracts and `Data/Repository`
/// holds implementations — the word names a concept, not a layer, and reading
/// it as one would have filed every repository protocol under data. The same
/// goes for `Model`, `Store`, `Gateway`, `Client`, `Service`, `Core` and
/// `Manager`. A gap in the generated configuration gets reviewed; a confident
/// wrong guess gets committed.
public enum LayerVocabulary {
    public static let byName: [String: Role] = {
        var table: [String: Role] = [:]

        for word in ["Tests", "Test", "Spec", "Specs", "Testing"] { table[word] = .tests }

        // Checked before the test words below would ever see it, because these
        // are production modules that exist to serve tests, not tests.
        for word in ["TestSupport", "TestingSupport", "TestKit", "TestHelpers",
                     "TestDoubles"] { table[word] = .testSupport }

        for word in ["DI", "Composition", "CompositionRoot", "Assembly", "Assemblies",
                     "Container", "Containers", "Injection", "Wiring", "Main", "App",
                     "Application", "Bootstrap"] { table[word] = .composition }

        // Singular and plural both, because a project picks one and keeps to
        // it. `Views/` was recognised and `View/` was not, so a module of
        // SwiftUI screens fell through to whatever its siblings suggested.
        for word in ["UI", "Presentation", "View", "Views", "Screen", "Screens",
                     "Scene", "Scenes", "ViewModel", "ViewModels",
                     "Presenter", "Presenters"] { table[word] = .presentation }

        for word in ["Data", "Persistence", "Infrastructure", "DTO", "DTOs",
                     "Remote", "Cache"] { table[word] = .data }

        for word in ["Domain", "Entities", "Entity", "UseCases", "UseCase",
                     "Interactor", "Interactors", "Business", "Rules"] { table[word] = .domain }

        for word in ["Library", "Libraries", "Utilities", "Utils"] { table[word] = .library }

        return table
    }()

    public struct Match: Sendable {
        public var role: Role
        /// The path segment that decided it, so a generated report can say
        /// what it actually read rather than something adjacent to it.
        public var segment: String
    }

    /// The role a path suggests, reading from the most specific directory
    /// outward. `Sources/DI` beats the `UI/` folder above it, because the
    /// nearer name is the more considered one.
    /// The nearest segment that says anything, reading outward.
    ///
    /// Distance decides before the kind of reading does. Trying `exactMatch`
    /// over the whole path first meant an ancestor could beat the segment next
    /// to the file: the reference project's `AuthUIDI` target has a source root
    /// at `UI/AuthUI/Sources/AuthUIDI`, and the `UI` three levels up won over
    /// the `DI` on the end of the directory itself — so three `*DI` modules
    /// read as presentation while nineteen read as composition.
    ///
    /// A suffix is still only read on the nearest segment. That is the weakest
    /// signal there is, and letting it run up the tree is what made every file
    /// under a folder called `ModularSwiftUI` a screen.
    public static func match(forDirectory directory: String) -> Match? {
        let segments = directory.split(separator: "/").map(String.init)
        if let segment = segments.first(where: isTestSegment) {
            return Match(role: .tests, segment: segment)
        }
        for (offset, segment) in segments.reversed().enumerated() {
            if let role = byName[segment] { return Match(role: role, segment: segment) }
            if offset == 0, let role = suffixRole(segment) { return Match(role: role, segment: segment) }
        }
        return nil
    }

    /// A directory that says its layer outright. Deliberate, so it outranks
    /// everything except a path the project declared itself.
    public static func exactMatch(forDirectory directory: String) -> Match? {
        let segments = directory.split(separator: "/").map(String.init)

        // A test anywhere in the path is a test, checked first and across the
        // whole path: test directories nest, and `Tests/FooTests/Support` is
        // support code for tests rather than a shared library.
        if let segment = segments.first(where: isTestSegment) {
            return Match(role: .tests, segment: segment)
        }

        for segment in segments.reversed() {
            if let role = byName[segment] { return Match(role: role, segment: segment) }
        }
        return nil
    }

    /// A directory that only *ends* in a layer word. The weakest signal there
    /// is, and it applies to the nearest segment alone, because in SwiftPM that
    /// is usually the module's own name — `Sources/AuthUIDI`.
    ///
    /// Ancestors are not read this way. A repository whose top folder is called
    /// `ModularSwiftUI` had every file beneath it reading as presentation,
    /// entities included, and renaming that one folder moved the whole tree to
    /// `domain`. A name that far from a file is not a statement about it.
    public static func suffixMatch(forDirectory directory: String) -> Match? {
        guard let last = directory.split(separator: "/").map(String.init).last,
              let role = suffixRole(last) else { return nil }
        return Match(role: role, segment: last)
    }

    public static func role(forDirectory directory: String) -> Role? {
        match(forDirectory: directory)?.role
    }

    /// Modules that carry their layer in their own name — `AuthUIDI`,
    /// `SnackbarUIHost`. Checked after the exact names so that a directory
    /// simply called `UI` is never read as a suffix.
    static func suffixRole(_ segment: String) -> Role? {
        guard segment.count > 2 else { return nil }
        if segment.hasSuffix("TestSupport") || segment.hasSuffix("TestKit") { return .testSupport }
        if segment.hasSuffix("DI") { return .composition }
        if segment.hasSuffix("UI") { return .presentation }
        return nil
    }

    static func isTestSegment(_ segment: String) -> Bool {
        if let role = byName[segment], role == .tests { return true }
        return segment.hasSuffix("Tests") || segment.hasSuffix("Spec") || segment.hasSuffix("Specs")
    }
}
