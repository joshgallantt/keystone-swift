import Catalog

/// A test data builder. Each test states the part of the product it cares
/// about and inherits sensible values for the rest — which is what keeps one
/// test's data from being another test's problem.
struct AProduct {
    private var id = "1"
    private var name = "Something"

    func named(_ name: String) -> AProduct {
        var copy = self
        copy.name = name
        copy.id = name.lowercased()
        return copy
    }

    func build() -> Item {
        Item(id: id, name: name)
    }
}
