public protocol BrowseCatalogUseCase: Sendable {
    func callAsFunction() async throws -> [Item]
}

public struct DefaultBrowseCatalogUseCase: BrowseCatalogUseCase {
    private let repository: any ItemRepository

    public init(repository: any ItemRepository) {
        self.repository = repository
    }

    public func callAsFunction() async throws -> [Item] {
        try await repository.items()
    }
}
