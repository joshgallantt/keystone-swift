import SwiftUI

public struct CatalogListView: View {
    @StateObject private var model: CatalogViewModel

    public init(model: CatalogViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    public var body: some View {
        List(model.names, id: \.self) { name in
            Text(name)
        }
    }
}
