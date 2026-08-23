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

        for word in ["UI", "Presentation", "Views", "Screens", "Scenes",
                     "ViewModels", "Presenters"] { table[word] = .presentation }

        for word in ["Data", "Persistence", "Infrastructure", "DTO", "DTOs",
                     "Remote", "Cache"] { table[word] = .data }

        for word in ["Domain", "Entities", "Entity", "UseCases", "UseCase",
                     "Interactors", "Business", "Rules"] { table[word] = .domain }

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
    public static func match(forDirectory directory: String) -> Match? {
        let segments = directory.split(separator: "/").map(String.init)

        // A test anywhere in the path is a test, checked first and across the
        // whole path: test directories nest, and `Tests/FooTests/Support` is
        // support code for tests rather than a shared library.
        if let segment = segments.first(where: isTestSegment) {
            return Match(role: .tests, segment: segment)
        }

        for segment in segments.reversed() {
            if let role = byName[segment] { return Match(role: role, segment: segment) }
            if let role = suffixRole(segment) { return Match(role: role, segment: segment) }
        }
        return nil
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
