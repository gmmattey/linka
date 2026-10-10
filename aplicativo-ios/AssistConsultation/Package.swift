// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AssistConsultation",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "AssistConsultation", targets: ["AssistConsultation"])
    ],
    dependencies: [
        .package(path: "../NetworkCore"),
        .package(path: "../NetworkInventory")
    ],
    targets: [
        .target(
            name: "AssistConsultation",
            dependencies: [
                .product(name: "NetworkCore", package: "NetworkCore"),
                .product(name: "NetworkInventory", package: "NetworkInventory")
            ],
            path: "Sources/AssistConsultation",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AssistConsultationTests",
            dependencies: [
                "AssistConsultation",
                .product(name: "NetworkCore", package: "NetworkCore")
            ],
            path: "Tests",
            resources: [.process("Fixtures")]
        )
    ]
)
