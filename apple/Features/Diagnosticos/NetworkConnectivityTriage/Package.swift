// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetworkConnectivityTriage",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "NetworkConnectivityTriage", targets: ["NetworkConnectivityTriage"])],
    targets: [
        .target(name: "NetworkConnectivityTriage", path: "Sources"),
        .testTarget(name: "NetworkConnectivityTriageTests", dependencies: ["NetworkConnectivityTriage"], path: "Tests")
    ]
)
