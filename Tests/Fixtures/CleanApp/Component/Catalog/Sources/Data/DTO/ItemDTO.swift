import Catalog

public struct ItemDTO: Decodable, Sendable {
    public let id: String
    public let name: String

    /// Mapped at the boundary, so the wire format stops here.
    var item: Item {
        Item(id: id, name: name)
    }
}
