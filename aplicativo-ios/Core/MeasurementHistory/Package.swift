// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeasurementHistory",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "MeasurementHistory", targets: ["MeasurementHistory"])
    ],
    dependencies: [
        .package(path: "../NetworkCore")
    ],
    targets: [
        .target(
            name: "MeasurementHistory",
            dependencies: [
                .product(name: "NetworkCore", package: "NetworkCore")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "MeasurementHistoryTests",
            dependencies: [
                "MeasurementHistory",
                .product(name: "NetworkCore", package: "NetworkCore")
            ],
            path: "Tests"
        )
    ]
)
