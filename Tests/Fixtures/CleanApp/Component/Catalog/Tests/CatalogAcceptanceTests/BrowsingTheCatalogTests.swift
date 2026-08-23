import Testing

/// Journeys, in the language a shopper would use. Nothing here names a
/// repository, a client or a DTO — the driver in Support/ knows about those so
/// that these tests do not have to, and so that the catalogue can be rebuilt
/// underneath them without a single line of this file changing.
@Test("A shopper browsing the catalogue sees everything the store sells")
func aShopperSeesWhatTheStoreSells() async throws {
    let store = Store()
    store.nowSells(AProduct().named("Kettle"))
    store.nowSells(AProduct().named("Toaster"))

    let shopper = Shopper(browsing: store)

    #expect(try await shopper.seesOnOffer() == ["Kettle", "Toaster"])
}

@Test("A shopper browsing an empty store is told there is nothing rather than shown an error")
func anEmptyStoreOffersNothing() async throws {
    let shopper = Shopper(browsing: Store())

    #expect(try await shopper.seesOnOffer().isEmpty)
}
