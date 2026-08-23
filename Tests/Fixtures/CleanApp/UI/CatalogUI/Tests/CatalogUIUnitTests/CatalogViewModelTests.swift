import Testing
@testable import CatalogUI

@MainActor
@Test("loading the catalogue puts every name on screen")
func loadingPublishesTheNames() async {
    let model = CatalogViewModel(browseCatalog: StubBrowseCatalog(returning: ["Kettle", "Toaster"]))

    await model.load()

    #expect(model.names == ["Kettle", "Toaster"])
}

@MainActor
@Test("a catalogue that fails to load leaves the screen empty rather than stale")
func failureLeavesTheScreenEmpty() async {
    let model = CatalogViewModel(browseCatalog: StubBrowseCatalog(failing: true))

    await model.load()

    #expect(model.names.isEmpty)
}
