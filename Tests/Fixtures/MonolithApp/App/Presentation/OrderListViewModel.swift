import Combine

@MainActor
public final class OrderListViewModel: ObservableObject {
    @Published public private(set) var references: [String] = []

    private let repository: any OrderRepository

    public init(repository: any OrderRepository) {
        self.repository = repository
    }

    public func load() async {
        references = ((try? await repository.orders()) ?? []).map(\.reference)
    }
}
