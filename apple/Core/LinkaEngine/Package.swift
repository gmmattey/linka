// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LinkaEngine",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "LinkaEngine",
            targets: ["LinkaEngine"]),
    ],
    targets: [
        .target(
            name: "LinkaEngine",
            path: "Core",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "LinkaEngineTests",
            dependencies: ["LinkaEngine"],
            path: "Tests"
        )
    ]
)
