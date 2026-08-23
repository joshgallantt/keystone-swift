import Catalog

/// A stub: canned answers, no recording. Named for its kind, because the kind
/// tells the reader that the tests using it verify state rather than behaviour.
struct StubBrowseCatalog: BrowseCatalogUseCase {
    private let names: [String]
    private let failing: Bool

    init(returning names: [String] = [], failing: Bool = false) {
        self.names = names
        self.failing = failing
    }

    func callAsFunction() async throws -> [Item] {
        if failing { throw StubFailure() }
        return names.map { Item(id: $0.lowercased(), name: $0) }
    }
}

struct StubFailure: Error {}
