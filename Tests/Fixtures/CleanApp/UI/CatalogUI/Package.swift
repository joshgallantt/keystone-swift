// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CatalogUI",
    products: [
        .library(name: "CatalogUI", targets: ["CatalogUI"]),
        .library(name: "CatalogUIDI", targets: ["CatalogUIDI"])
    ],
    dependencies: [
        .package(path: "../../Component/Catalog")
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
        )
    ]
)
