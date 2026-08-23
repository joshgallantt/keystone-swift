import Catalog

/// The snapshot suite keeps its own double rather than borrowing the unit
/// suite's. Each tier's Support belongs to that tier, and two doubles sharing a
/// name across a repository read as one thing in review while behaving as two.
struct StubPopulatedCatalog: BrowseCatalogUseCase {
    func callAsFunction() async throws -> [Item] {
        [Item(id: "kettle", name: "Kettle"), Item(id: "toaster", name: "Toaster")]
    }
}
