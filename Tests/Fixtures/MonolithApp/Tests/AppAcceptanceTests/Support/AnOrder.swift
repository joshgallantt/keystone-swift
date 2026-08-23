/// A builder. Each test states the one field it cares about and inherits the
/// rest, so no test is reading data another test owns.
struct AnOrder {
    private var reference = "A-0"

    func referenced(_ reference: String) -> AnOrder {
        var copy = self
        copy.reference = reference
        return copy
    }

    func build() -> Order {
        Order(reference: reference)
    }
}
