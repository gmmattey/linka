// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetscopeEvidence",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "NetscopeEvidence", targets: ["NetscopeEvidence"])
    ],
    dependencies: [
        .package(path: "../NetworkCore")
    ],
    targets: [
        .target(
            name: "NetscopeEvidence",
            dependencies: [
                .product(name: "NetworkCore", package: "NetworkCore")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "NetscopeEvidenceTests",
            dependencies: [
                "NetscopeEvidence",
                .product(name: "NetworkCore", package: "NetworkCore")
            ],
            path: "Tests",
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
