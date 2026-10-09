// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetworkInventory",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "NetworkInventory", targets: ["NetworkInventory"])
    ],
    dependencies: [
        .package(path: "../NetworkProfiles"),
        .package(path: "../NetworkCore")
    ],
    targets: [
        .target(
            name: "NetworkInventory",
            dependencies: [
                .product(name: "NetworkProfiles", package: "NetworkProfiles"),
                .product(name: "NetworkCore", package: "NetworkCore")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "NetworkInventoryTests",
            dependencies: [
                "NetworkInventory",
                .product(name: "NetworkCore", package: "NetworkCore")
            ],
            path: "Tests",
            resources: [.process("Fixtures")]
        )
    ]
)
