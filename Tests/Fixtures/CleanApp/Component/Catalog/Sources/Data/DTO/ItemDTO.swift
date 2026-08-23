import Catalog

public struct ItemDTO: Decodable, Sendable {
    public let id: String
    public let name: String

    /// Mapped at the boundary, so the wire format stops here. Declared in the
    /// type's own body rather than in an extension: the DTO has one shape, and
    /// it is the one written here.
    var item: Item {
        Item(id: id, name: name)
    }
}
