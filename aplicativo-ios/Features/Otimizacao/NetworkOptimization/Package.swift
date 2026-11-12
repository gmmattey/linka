// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetworkOptimization",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "NetworkOptimization", targets: ["NetworkOptimization"])],
    dependencies: [
        .package(path: "../../../Core/NetworkCore"),
        .package(path: "../../Diagnosticos/NetworkInsights")
    ],
    targets: [
        .target(
            name: "NetworkOptimization",
            dependencies: [
                .product(name: "NetworkCore", package: "NetworkCore"),
                .product(name: "NetworkInsights", package: "NetworkInsights")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "NetworkOptimizationTests",
            dependencies: [
                "NetworkOptimization",
                .product(name: "NetworkCore", package: "NetworkCore")
            ],
            path: "Tests"
        )
    ]
)
