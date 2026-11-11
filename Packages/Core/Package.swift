// swift-tools-version: 6.2
import PackageDescription

/// Core game logic, split along clean architecture boundaries:
///
/// - `GameDomain`: entities and value types. No dependencies.
/// - `GameData`: loads and validates game data (repository pattern).
/// - `GameSimulation`: world state, simulation systems, commands and the
///   background engine.
/// - `GamePersistence`: saving and loading games (repository pattern).
///
/// None of these modules import SwiftUI, AppKit or RealityKit.
let package = Package(
    name: "Core",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "GameDomain", targets: ["GameDomain"]),
        .library(name: "GameData", targets: ["GameData"]),
        .library(name: "GameSimulation", targets: ["GameSimulation"]),
        .library(name: "GamePersistence", targets: ["GamePersistence"]),
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
        .target(
            name: "GamePersistence",
            dependencies: ["GameDomain", "GameSimulation"]
        ),
        .testTarget(name: "GameDomainTests", dependencies: ["GameDomain"]),
        .testTarget(name: "GameDataTests", dependencies: ["GameData"]),
        .testTarget(name: "GameSimulationTests", dependencies: ["GameSimulation", "GameData"]),
        .testTarget(name: "GamePersistenceTests", dependencies: ["GamePersistence", "GameSimulation", "GameData"]),
    ],
    swiftLanguageModes: [.v6]
)
