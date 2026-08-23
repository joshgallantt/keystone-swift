/// The world. Holding what has been ordered is the warehouse's job, not the
/// customer's — the driver reads as nonsense the moment an actor is made
/// responsible for state it could not possibly control.
final class Warehouse {
    private(set) var placed: [Order] = []

    func record(_ order: Order) {
        placed.append(order)
    }
}
