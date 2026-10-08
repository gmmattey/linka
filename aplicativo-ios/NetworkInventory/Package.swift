// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "NetworkInventory", platforms: [.iOS(.v16), .macOS(.v13)], products: [.library(name: "NetworkInventory", targets: ["NetworkInventory"])], dependencies: [.package(path: "../NetworkProfiles")], targets: [.target(name: "NetworkInventory", dependencies: [.product(name: "NetworkProfiles", package: "NetworkProfiles")], path: "Sources"), .testTarget(name: "NetworkInventoryTests", dependencies: ["NetworkInventory"], path: "Tests")])
