import Testing
@testable import Catalog

@Test("an item keeps the name it was given")
func itemKeepsTheNameItWasGiven() {
    #expect(Item(id: "1", name: "Kettle").name == "Kettle")
}
