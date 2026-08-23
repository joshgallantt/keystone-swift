import Catalog

/// The actor. Everything the tests can do, phrased as things a person does.
/// This is the only vocabulary the acceptance suite is allowed; when a test
/// needs something new, this is what grows.
struct Shopper {
    private let browse: any BrowseCatalogUseCase

    init(browsing store: Store) {
        self.browse = DefaultBrowseCatalogUseCase(repository: InMemoryItemRepository(store: store))
    }

    func seesOnOffer() async throws -> [String] {
        try await browse().map(\.name)
    }
}

/// A working stand-in for the real repository, wired to the store rather than
/// to a network. A fake in Meszaros' sense: it works, it is just unfit for
/// production.
private struct InMemoryItemRepository: ItemRepository {
    let store: Store

    func items() async throws -> [Item] {
        store.stock
    }
}
