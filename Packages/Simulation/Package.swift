// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Simulation",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Simulation", targets: ["Simulation"]),
    ],
    targets: [
        .target(
            name: "Simulation",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SimulationTests",
            dependencies: ["Simulation"]
        ),
    ]
)
