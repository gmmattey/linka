// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetworkDNSBenchmark",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "NetworkDNSBenchmark", targets: ["NetworkDNSBenchmark"])],
    targets: [
        .target(name: "NetworkDNSBenchmark", path: "Sources"),
        .testTarget(name: "NetworkDNSBenchmarkTests", dependencies: ["NetworkDNSBenchmark"], path: "Tests")
    ]
)
