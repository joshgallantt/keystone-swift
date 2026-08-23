import Testing

@Test("an order keeps the reference it was given")
func orderKeepsItsReference() {
    #expect(Order(reference: "A-1").reference == "A-1")
}

@Test("two orders with the same reference are the same order")
func ordersCompareByValue() {
    #expect(Order(reference: "A-1") == Order(reference: "A-1"))
}

@MainActor
@Test("loading puts every reference on screen")
func loadingPublishesTheReferences() async {
    let model = OrderListViewModel(repository: StubOrderRepository(returning: ["A-1", "A-2"]))

    await model.load()

    #expect(model.references == ["A-1", "A-2"])
}
