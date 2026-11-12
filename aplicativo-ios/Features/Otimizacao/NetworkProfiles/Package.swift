// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetworkProfiles",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "NetworkProfiles", targets: ["NetworkProfiles"])
    ],
    dependencies: [
        .package(path: "../../../Core/NetworkCore")
    ],
    targets: [
        .target(
            name: "NetworkProfiles",
            dependencies: [
                .product(name: "NetworkCore", package: "NetworkCore")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "NetworkProfilesTests",
            dependencies: ["NetworkProfiles"],
            path: "Tests"
        )
    ]
)
