import Catalog
import CatalogData
import Networking

public struct CatalogDI: Sendable {
    private let repository: any ItemRepository

    public init(client: any HTTPClient) {
        self.repository = DefaultItemRepository(client: client)
    }

    public var browseCatalog: any BrowseCatalogUseCase {
        DefaultBrowseCatalogUseCase(repository: repository)
    }
}
