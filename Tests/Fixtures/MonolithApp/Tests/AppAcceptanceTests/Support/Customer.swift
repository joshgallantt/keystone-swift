/// The actor, and the whole vocabulary this suite is allowed. Support code may
/// name the concrete repository; the tests themselves may not, which is what
/// lets the storage underneath be replaced without touching a journey.
struct Customer {
    private let warehouse: Warehouse

    init(buyingFrom warehouse: Warehouse) {
        self.warehouse = warehouse
    }

    func places(_ order: AnOrder) async throws {
        warehouse.record(order.build())
    }

    func seesOrders() async throws -> [String] {
        try await InMemoryOrderRepository(warehouse: warehouse).orders().map(\.reference)
    }
}

/// A fake in Meszaros' sense: it works, it is simply unfit for production.
private struct InMemoryOrderRepository: OrderRepository {
    let warehouse: Warehouse

    func orders() async throws -> [Order] {
        warehouse.placed
    }
}
