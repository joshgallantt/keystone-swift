import SnapshotTesting
import SwiftUI
import Testing
@testable import CatalogUI

/// The one thing neither other tier can check: what the screen looks like.
/// Recorded images are committed, so the suite can actually fail.
@MainActor
@Test("the catalogue list renders a row for every item")
func catalogListRendersEveryRow() {
    let view = CatalogListView(model: CatalogViewModel(browseCatalog: StubPopulatedCatalog()))

    assertSnapshot(of: view, as: .image(layout: .device(config: .iPhone13)))
}
