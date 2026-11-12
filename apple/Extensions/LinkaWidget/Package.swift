// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LinkaWidget",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "LinkaWidget", targets: ["LinkaWidget"])
    ],
    dependencies: [
        .package(path: "../LinkaWidgetShared")
    ],
    targets: [
        .target(
            name: "LinkaWidget",
            dependencies: ["LinkaWidgetShared"],
            path: "Sources",
            exclude: ["LinkaSpeedTestWidget.swift", "LinkaWidgetBundle.swift"]
        ),
        .testTarget(
            name: "LinkaWidgetTests",
            dependencies: ["LinkaWidget", "LinkaWidgetShared"],
            path: "Tests"
        )
    ]
)
