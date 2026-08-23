import CatalogDI
import CatalogUI

public struct CatalogUIDI {
    private let catalog: CatalogDI

    public init(catalog: CatalogDI) {
        self.catalog = catalog
    }

    @MainActor
    public func catalogList() -> CatalogListView {
        CatalogListView(model: CatalogViewModel(browseCatalog: catalog.browseCatalog))
    }
}
