import Catalog

/// Stand-ins for the protocols this component declares, published as a product
/// so every suite that needs one shares a single definition.
///
/// The unit suite and the snapshot suite used to keep a copy each. They were
/// not the same copy — one could be made to fail and one could not — and
/// nothing said so, because a double that disagrees with another double breaks
/// no test. Whoever owns the protocol owns the stand-in for it.
///
/// Every member is `public`: a shared module is consumed with a plain `import`,
/// and `@testable` is not a substitute — it compiles against internal members
/// and then fails at the link step.
public struct StubBrowseCatalog: BrowseCatalogUseCase {
    private let names: [String]
    private let failing: Bool

    public init(returning names: [String] = [], failing: Bool = false) {
        self.names = names
        self.failing = failing
    }

    public func callAsFunction() async throws -> [Item] {
        if failing { throw StubFailure() }
        return names.map { Item(id: $0.lowercased(), name: $0) }
    }
}

public struct StubFailure: Error {
    public init() {}
}
