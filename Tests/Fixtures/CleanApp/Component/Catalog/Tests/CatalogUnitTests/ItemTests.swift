import Testing
@testable import Catalog

@Test("an item keeps the name it was given")
func itemKeepsTheNameItWasGiven() {
    #expect(Item(id: "1", name: "Kettle").name == "Kettle")
}

@Test("two items with the same identity and name are the same item")
func itemsCompareByValue() {
    #expect(Item(id: "1", name: "Kettle") == Item(id: "1", name: "Kettle"))
}

@Test("an item is not equal to one with a different identity")
func itemsWithDifferentIdentitiesDiffer() {
    #expect(Item(id: "1", name: "Kettle") != Item(id: "2", name: "Kettle"))
}
