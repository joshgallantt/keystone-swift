import Catalog
import Foundation
import Networking

public struct DefaultItemRepository: ItemRepository {
    private let client: any HTTPClient

    public init(client: any HTTPClient) {
        self.client = client
    }

    public func items() async throws -> [Item] {
        let payload = try await client.get("/items")
        return try JSONDecoder().decode([ItemDTO].self, from: payload).map(\.item)
    }
}
