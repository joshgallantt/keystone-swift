// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CatalogUI",
    products: [
        .library(name: "CatalogUI", targets: ["CatalogUI"]),
        .library(name: "CatalogUIDI", targets: ["CatalogUIDI"])
    ],
    dependencies: [
        .package(path: "../../Component/Catalog"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.0")
    ],
    targets: [
        .target(
            name: "CatalogUI",
            dependencies: [.product(name: "Catalog", package: "Catalog")],
            path: "Sources/UI"
        ),
        .target(
            name: "CatalogUIDI",
            dependencies: ["CatalogUI", .product(name: "CatalogDI", package: "Catalog")],
            path: "Sources/DI"
        ),
        .testTarget(
            name: "CatalogUIUnitTests",
            dependencies: ["CatalogUI", .product(name: "Catalog", package: "Catalog")],
            path: "Tests/CatalogUIUnitTests"
        ),
        .testTarget(
            name: "CatalogUISnapshotTests",
            dependencies: [
                "CatalogUI",
                .product(name: "Catalog", package: "Catalog"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests/CatalogUISnapshotTests"
        )
    ]
)
