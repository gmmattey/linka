// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetworkCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "NetworkCore", targets: ["NetworkCore"])
    ],
    targets: [
        .target(name: "NetworkCore", path: "Sources"),
        .testTarget(
            name: "NetworkCoreTests",
            dependencies: ["NetworkCore"],
            path: "Tests"
        )
    ]
)
