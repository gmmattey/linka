// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LinkaWidgetShared",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "LinkaWidgetShared", targets: ["LinkaWidgetShared"])
    ],
    targets: [
        .target(name: "LinkaWidgetShared", path: "Sources"),
        .testTarget(
            name: "LinkaWidgetSharedTests",
            dependencies: ["LinkaWidgetShared"],
            path: "Tests"
        )
    ]
)
