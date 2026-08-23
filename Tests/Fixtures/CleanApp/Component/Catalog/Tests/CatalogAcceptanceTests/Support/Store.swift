import Catalog

/// The world the journeys happen in. Setting up what exists is the store's
/// job, not the shopper's — a shopper cannot make a shop stock something, and
/// a driver that pretends otherwise reads as nonsense in the test.
final class Store {
    private(set) var stock: [Item] = []

    func nowSells(_ product: AProduct) {
        stock.append(product.build())
    }
}
