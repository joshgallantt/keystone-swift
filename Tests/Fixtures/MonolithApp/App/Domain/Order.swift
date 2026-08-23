public struct Order: Equatable, Sendable {
    public let reference: String

    public init(reference: String) {
        self.reference = reference
    }
}

public protocol OrderRepository: Sendable {
    func orders() async throws -> [Order]
}
