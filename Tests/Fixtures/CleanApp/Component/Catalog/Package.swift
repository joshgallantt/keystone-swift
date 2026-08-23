// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Catalog",
    products: [
        .library(name: "Catalog", targets: ["Catalog"]),
        .library(name: "CatalogData", targets: ["CatalogData"]),
        .library(name: "CatalogDI", targets: ["CatalogDI"])
    ],
    dependencies: [
        .package(path: "../../Library/Networking")
    ],
    targets: [
        .target(
            name: "Catalog",
            path: "Sources",
            exclude: ["Data", "DI"],
            sources: ["Domain"]
        ),
        .target(
            name: "CatalogData",
            dependencies: ["Catalog", .product(name: "Networking", package: "Networking")],
            path: "Sources",
            exclude: ["Domain", "DI"],
            sources: ["Data"]
        ),
        .target(
            name: "CatalogDI",
            dependencies: ["Catalog", "CatalogData", .product(name: "Networking", package: "Networking")],
            path: "Sources/DI"
        ),
        .testTarget(
            name: "CatalogUnitTests",
            dependencies: ["Catalog"],
            path: "Tests/CatalogUnitTests"
        ),
        .testTarget(
            name: "CatalogAcceptanceTests",
            dependencies: ["Catalog"],
            path: "Tests/CatalogAcceptanceTests"
        )
    ]
)
