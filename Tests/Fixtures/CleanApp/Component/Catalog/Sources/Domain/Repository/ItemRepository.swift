/// The contract lives with the layer that needs it satisfied.
public protocol ItemRepository: Sendable {
    func items() async throws -> [Item]
}
