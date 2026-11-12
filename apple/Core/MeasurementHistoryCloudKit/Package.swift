// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeasurementHistoryCloudKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "MeasurementHistoryCloudKit", targets: ["MeasurementHistoryCloudKit"])
    ],
    dependencies: [
        .package(path: "../NetworkCore"),
        .package(path: "../MeasurementHistory")
    ],
    targets: [
        .target(
            name: "MeasurementHistoryCloudKit",
            dependencies: [
                .product(name: "NetworkCore", package: "NetworkCore"),
                .product(name: "MeasurementHistory", package: "MeasurementHistory")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "MeasurementHistoryCloudKitTests",
            dependencies: [
                "MeasurementHistoryCloudKit",
                .product(name: "NetworkCore", package: "NetworkCore"),
                .product(name: "MeasurementHistory", package: "MeasurementHistory")
            ],
            path: "Tests"
        )
    ]
)
