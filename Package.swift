// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "keystone-swift",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "keystone-swift", targets: ["keystone-swift"]),
        .library(name: "KeystoneKit", targets: ["KeystoneKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.0")
    ],
    targets: [
        .target(
            name: "KeystoneKit",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ]
        ),
        .executableTarget(
            name: "keystone-swift",
            dependencies: ["KeystoneKit"]
        ),
        .testTarget(
            name: "KeystoneKitTests",
            dependencies: ["KeystoneKit"]
        )
    ]
)
