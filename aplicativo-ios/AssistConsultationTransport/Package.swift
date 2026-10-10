// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AssistConsultationTransport",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "AssistConsultationTransport", targets: ["AssistConsultationTransport"])
    ],
    dependencies: [
        .package(path: "../AssistConsultation")
    ],
    targets: [
        .target(
            name: "AssistConsultationTransport",
            dependencies: ["AssistConsultation"],
            path: "Sources"
        ),
        .testTarget(
            name: "AssistConsultationTransportTests",
            dependencies: ["AssistConsultationTransport", "AssistConsultation"],
            path: "Tests"
        )
    ]
)
