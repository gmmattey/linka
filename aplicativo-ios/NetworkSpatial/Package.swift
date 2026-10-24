// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetworkSpatial",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "NetworkSpatial",
            targets: ["NetworkSpatial"]
        )
    ],
    dependencies: [
        .package(path: "../NetworkCore")
    ],
    targets: [
        .target(
            name: "NetworkSpatial",
            dependencies: [
                .product(name: "NetworkCore", package: "NetworkCore")
            ],
            path: "Sources/NetworkSpatial",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "NetworkSpatialTests",
            dependencies: ["NetworkSpatial"],
            path: "Tests/NetworkSpatialTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
