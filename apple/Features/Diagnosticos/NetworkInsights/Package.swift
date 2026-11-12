// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetworkInsights",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "NetworkInsights", targets: ["NetworkInsights"])
    ],
    dependencies: [
        .package(path: "../../../Core/NetworkCore")
    ],
    targets: [
        .target(
            name: "NetworkInsights",
            dependencies: [
                .product(name: "NetworkCore", package: "NetworkCore")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "NetworkInsightsTests",
            dependencies: [
                "NetworkInsights",
                .product(name: "NetworkCore", package: "NetworkCore")
            ],
            path: "Tests"
        )
    ]
)
