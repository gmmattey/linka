// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetworkDiagnostics",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "NetworkDiagnostics", targets: ["NetworkDiagnostics"])
    ],
    dependencies: [
        .package(path: "../../../Core/NetworkCore"),
        .package(path: "../../Assist/NetworkAssist"),
        .package(path: "../NetworkInsights"),
        .package(path: "../../../Core/MeasurementHistory")
    ],
    targets: [
        .target(
            name: "NetworkDiagnostics",
            dependencies: [
                .product(name: "NetworkCore", package: "NetworkCore"),
                .product(name: "NetworkAssist", package: "NetworkAssist"),
                .product(name: "NetworkInsights", package: "NetworkInsights"),
                .product(name: "MeasurementHistory", package: "MeasurementHistory")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "NetworkDiagnosticsTests",
            dependencies: [
                "NetworkDiagnostics",
                .product(name: "NetworkCore", package: "NetworkCore"),
                .product(name: "NetworkAssist", package: "NetworkAssist"),
                .product(name: "MeasurementHistory", package: "MeasurementHistory")
            ],
            path: "Tests"
        )
    ]
)
