// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LinkaEntitlements",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "LinkaEntitlements", targets: ["LinkaEntitlements"])
    ],
    targets: [
        .target(name: "LinkaEntitlements", path: "Sources"),
        .testTarget(
            name: "LinkaEntitlementsTests",
            dependencies: ["LinkaEntitlements"],
            path: "Tests"
        )
    ]
)
