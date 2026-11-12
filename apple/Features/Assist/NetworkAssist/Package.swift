// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetworkAssist",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "NetworkAssist", targets: ["NetworkAssist"])
    ],
    dependencies: [
        .package(path: "../../../Core/NetworkCore")
    ],
    targets: [
        .target(
            name: "NetworkAssist",
            dependencies: [
                .product(name: "NetworkCore", package: "NetworkCore")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "NetworkAssistTests",
            dependencies: [
                "NetworkAssist",
                .product(name: "NetworkCore", package: "NetworkCore")
            ],
            path: "Tests"
        )
    ]
)
