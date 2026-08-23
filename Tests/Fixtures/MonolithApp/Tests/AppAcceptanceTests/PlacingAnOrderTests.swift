import Testing

/// A different domain from the other fixture on purpose: nothing in the tool
/// knows what an app is about, and two fixtures that disagree about their
/// subject are the cheapest way to keep that true.
@Test("Someone who places an order can see it among their orders afterwards")
func aPlacedOrderShowsUpAfterwards() async throws {
    let warehouse = Warehouse()
    let customer = Customer(buyingFrom: warehouse)

    try await customer.places(AnOrder().referenced("A-1"))

    #expect(try await customer.seesOrders() == ["A-1"])
}

@Test("Someone who has ordered nothing is shown an empty list rather than an error")
func noOrdersIsAnEmptyList() async throws {
    let customer = Customer(buyingFrom: Warehouse())

    #expect(try await customer.seesOrders().isEmpty)
}
