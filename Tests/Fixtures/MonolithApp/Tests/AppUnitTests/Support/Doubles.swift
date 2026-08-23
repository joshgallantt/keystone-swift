/// A stub: canned answers, nothing recorded. The kind is in the name because
/// it tells the reader that the tests using it check state rather than
/// behaviour.
struct StubOrderRepository: OrderRepository {
    private let references: [String]

    init(returning references: [String]) {
        self.references = references
    }

    func orders() async throws -> [Order] {
        references.map(Order.init(reference:))
    }
}
