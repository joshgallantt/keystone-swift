import Catalog
import Combine

@MainActor
public final class CatalogViewModel: ObservableObject {
    @Published public private(set) var names: [String] = []

    private let browseCatalog: any BrowseCatalogUseCase

    public init(browseCatalog: any BrowseCatalogUseCase) {
        self.browseCatalog = browseCatalog
    }

    public func load() async {
        names = ((try? await browseCatalog()) ?? []).map(\.name)
    }
}
