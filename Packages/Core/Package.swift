// swift-tools-version: 6.2
import PackageDescription

/// Core game logic, split along clean architecture boundaries:
///
/// - `GameDomain`: entities and value types. No dependencies.
/// - `GameData`: loads and validates game data (repository pattern).
/// - `GameSimulation`: world state, simulation systems, commands and the
///   background engine.
///
/// None of these modules import SwiftUI, AppKit or RealityKit.
let package = Package(
    name: "Core",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "GameDomain", targets: ["GameDomain"]),
        .library(name: "GameData", targets: ["GameData"]),
        .library(name: "GameSimulation", targets: ["GameSimulation"]),
    ],
    targets: [
        .target(name: "GameDomain"),
        .target(
            name: "GameData",
            dependencies: ["GameDomain"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "GameSimulation",
            dependencies: ["GameDomain"]
        ),
        .testTarget(name: "GameDomainTests", dependencies: ["GameDomain"]),
        .testTarget(name: "GameDataTests", dependencies: ["GameData"]),
        .testTarget(name: "GameSimulationTests", dependencies: ["GameSimulation", "GameData"]),
    ],
    swiftLanguageModes: [.v6]
)
