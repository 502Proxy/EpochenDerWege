import Foundation
import GameData
import GameDomain
@testable import GamePersistence
@testable import GameSimulation
import Testing

@Suite("Save games")
struct SaveGameTests {
    /// A fresh, empty directory per test.
    private func makeRepository() throws -> FileSaveGameRepository {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "EpochenDerWegeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return FileSaveGameRepository(directory: directory)
    }

    /// A generated world with a region, some buildings, a line and a few days of history.
    private func playedSimulation() throws -> Simulation {
        let catalog = try BundledCatalogRepository().loadCatalog()
        var simulation = Simulation(world: WorldFactory.makeWorld(catalog: catalog, seed: 7, mapSize: 128))
        let start = try #require(simulation.world.startCell)
        simulation.execute(PlaceBuildingCommand(buildingType: "grainFarm", cell: start.offset(dx: 1, dz: 0)))
        simulation.execute(ZoneCommand(cells: [start.offset(dx: -1, dz: 0)], kind: .industrial))
        simulation.execute(PlaceBuildingCommand(buildingType: "mill", cell: start.offset(dx: -1, dz: 0)))
        simulation.execute(BuildRoadCommand(cells: RoadPlanner.path(from: start.offset(dx: -4, dz: 3), to: start.offset(dx: 4, dz: 3))))
        simulation.advance(days: 20)
        return simulation
    }

    private func expectSameState(_ a: WorldState, _ b: WorldState) {
        #expect(a.clock == b.clock)
        #expect(a.treasury == b.treasury)
        #expect(a.ledger == b.ledger)
        #expect(a.goodsStatistics == b.goodsStatistics)
        #expect(a.buildings == b.buildings)
        #expect(a.carriers == b.carriers)
        #expect(a.roads == b.roads)
        #expect(a.tunnels == b.tunnels)
        #expect(a.zones == b.zones)
        #expect(a.lines == b.lines)
        #expect(a.vehicles == b.vehicles)
        #expect(a.towns == b.towns)
        #expect(a.settlementLevel == b.settlementLevel)
        #expect(a.events == b.events)
        #expect(a.startCell == b.startCell)
    }

    @Test func roundTripKeepsTheWorld() throws {
        let repository = try makeRepository()
        let world = try playedSimulation().world
        let entry = try repository.save(world, named: "First town")

        let restored = try repository.load(entry.id)
        expectSameState(world, restored)
        // Lookup tables are rebuilt.
        for building in world.buildings {
            #expect(restored.building(at: building.cell)?.id == building.id)
        }
        // Terrain, including deposits.
        let terrain = restored.terrain
        #expect(terrain.size == world.terrain.size)
        for z in stride(from: 0, to: terrain.size, by: 3) {
            for x in stride(from: 0, to: terrain.size, by: 3) {
                let cell = GridPoint(x: x, z: z)
                #expect(terrain.biome(at: cell) == world.terrain.biome(at: cell))
                #expect(terrain.deposit(at: cell) == world.terrain.deposit(at: cell))
                #expect(terrain.cornerHeight(x: x, z: z) == world.terrain.cornerHeight(x: x, z: z))
            }
        }
    }

    @Test func restoredGameContinuesExactlyLikeTheOriginal() throws {
        let repository = try makeRepository()
        var original = try playedSimulation()
        let entry = try repository.save(original.world, named: "Branch")
        var restored = Simulation(world: try repository.load(entry.id))

        original.advance(days: 30)
        restored.advance(days: 30)
        expectSameState(original.world, restored.world)
    }

    @Test func listShowsSummariesNewestFirstAndReplacesByName() throws {
        let repository = try makeRepository()
        let world = try playedSimulation().world
        try repository.save(world, named: "Alpha")
        try repository.save(world, named: "Beta")
        try repository.save(world, named: "Alpha")

        let entries = try repository.list()
        #expect(entries.count == 2)
        let alpha = try #require(entries.first { $0.summary.name == "Alpha" })
        #expect(alpha.summary.population == world.population)
        #expect(alpha.summary.treasury == world.treasury)
        #expect(alpha.summary.year == world.clock.year)

        try repository.delete(alpha.id)
        #expect(try repository.list().map(\.summary.name) == ["Beta"])
        #expect(throws: SaveGameError.notFound(alpha.id)) { try repository.load(alpha.id) }
    }

    @Test func foreignAndNewerFilesAreRejected() throws {
        let repository = try makeRepository()
        try FileManager.default.createDirectory(at: repository.directory, withIntermediateDirectories: true)
        let foreign = "notes.\(FileSaveGameRepository.fileExtension)"
        try Data("hello".utf8).write(to: repository.directory.appending(path: foreign))
        #expect(try repository.list().isEmpty)
        #expect(throws: SaveGameError.notASaveGame) { try repository.load(foreign) }

        let world = try playedSimulation().world
        var data = try FileSaveGameRepository.encode(world, summary: SaveGameSummary(name: "Future", savedAt: .now, world: world))
        data[data.startIndex + 7] = FileSaveGameRepository.formatVersion + 1
        let future = "future.\(FileSaveGameRepository.fileExtension)"
        try data.write(to: repository.directory.appending(path: future))
        #expect(throws: SaveGameError.newerFormat(Int(FileSaveGameRepository.formatVersion) + 1)) { try repository.load(future) }
    }

    @Test func fileNamesAreSafe() {
        #expect(FileSaveGameRepository.fileName(for: "My town") == "My-town.edwsave")
        #expect(FileSaveGameRepository.fileName(for: "../../etc") == "etc.edwsave")
        #expect(FileSaveGameRepository.fileName(for: "///") == "Save.edwsave")
    }

    @Test func runLengthCodingRoundTrips() {
        let values: [Biome] = [.grass, .grass, .forest, .grass, .water, .water, .water]
        let encoded = RunLengthEncoded(values)
        #expect(encoded.runs.count == 4)
        #expect(encoded.values == values)
    }
}
