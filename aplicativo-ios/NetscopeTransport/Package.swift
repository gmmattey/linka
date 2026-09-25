// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetscopeTransport",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "NetscopeTransport", targets: ["NetscopeTransport"])
    ],
    dependencies: [
        .package(path: "../NetscopeEvidence")
    ],
    targets: [
        .target(
            name: "NetscopeTransport",
            dependencies: ["NetscopeEvidence"],
            path: "Sources",
            linkerSettings: [
                .linkedFramework("DeviceCheck", .when(platforms: [.iOS])),
                .linkedFramework("Security", .when(platforms: [.iOS]))
            ]
        ),
        .testTarget(
            name: "NetscopeTransportTests",
            dependencies: ["NetscopeTransport", "NetscopeEvidence"],
            path: "Tests"
        )
    ]
)
