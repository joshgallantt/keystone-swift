import Foundation

public struct DefaultOrderRepository: OrderRepository {
    public init() {}

    public func orders() async throws -> [Order] {
        [Order(reference: "A-1")]
    }
}
