import GameDomain
@testable import GameSimulation
import Testing

@Suite("Residential zones")
struct ZoneTests {
    /// Flat map with the settlement at (16, 16), a road along z = 10 and a zone above it.
    private func zonedSimulation(rules: ((inout GameRules) -> Void)? = nil) throws -> Simulation {
        var simulation = try Fixtures.flatSimulation(rules: rules)
        simulation.execute(BuildRoadCommand(cells: RoadPlanner.path(from: GridPoint(x: 8, z: 10), to: GridPoint(x: 24, z: 10))))
        simulation.execute(ZoneCommand(cells: ZonePlanner.rectangle(from: GridPoint(x: 8, z: 8), to: GridPoint(x: 24, z: 9)), kind: .residential))
        return simulation
    }

    @Test func rectangleCoversAllCells() {
        let cells = ZonePlanner.rectangle(from: GridPoint(x: 3, z: 1), to: GridPoint(x: 1, z: 2))
        #expect(cells.count == 6)
        #expect(Set(cells).contains(GridPoint(x: 2, z: 1)))
    }

    @Test func zoningIsFreeAndCanBeRemoved() throws {
        var simulation = try Fixtures.flatSimulation(settlement: false)
        let start = simulation.world.treasury
        let cells = ZonePlanner.rectangle(from: GridPoint(x: 0, z: 0), to: GridPoint(x: 2, z: 2))
        simulation.execute(ZoneCommand(cells: cells, kind: .residential))
        #expect(simulation.world.zones.count == 9)
        #expect(simulation.world.treasury == start)
        #expect(simulation.lastEvent == .zoneChanged(kind: .residential, cells: 9))

        simulation.execute(ZoneCommand(cells: [GridPoint(x: 1, z: 1)], kind: nil))
        #expect(simulation.world.zones.count == 8)
    }

    @Test func waterCannotBeZoned() throws {
        let catalog = try Fixtures.catalog()
        let terrain = Terrain.flat(size: 8).replacingBiome(at: GridPoint(x: 1, z: 1), with: .water)
        var simulation = Simulation(world: WorldFactory.makeWorld(catalog: catalog, terrain: terrain, foundSettlement: false))
        simulation.execute(ZoneCommand(cells: ZonePlanner.rectangle(from: GridPoint(x: 0, z: 0), to: GridPoint(x: 1, z: 1)), kind: .residential))
        #expect(simulation.world.zones[GridPoint(x: 1, z: 1)] == nil)
        #expect(simulation.world.zones.count == 3)
    }

    @Test func townBuildsHousesNextToRoadsWhenJobsAreOpen() throws {
        var simulation = try zonedSimulation()
        // Open jobs: more workplaces than residents.
        for x in 13...19 {
            try simulation.place("grainFarm", x: x, z: 20)
        }
        let houses = simulation.world.buildings.filter { $0.category == .housing }.count
        simulation.advance(days: simulation.world.rules.zoneGrowthIntervalDays)

        let newHouses = simulation.world.buildings.filter { $0.category == .housing }
        #expect(newHouses.count == houses + 1)
        let built = try #require(newHouses.last)
        #expect(simulation.world.zones[built.cell] == .residential)
        #expect(TownGrowthSystem.isNextToRoad(built.cell, in: simulation.world))
        #expect(built.cell.z == 9)
        #expect(simulation.world.events.contains { $0.event == .townGrew(built.id) })
    }

    @Test func townWaitsUntilNewHousesAreMovedInto() throws {
        var simulation = try zonedSimulation()
        for x in 13...19 {
            try simulation.place("grainFarm", x: x, z: 20)
        }
        let houses = simulation.world.buildings.filter { $0.category == .housing }.count
        // The next growth check only builds again once the new house has residents,
        // so there is never more than one empty house waiting for food.
        simulation.advance(days: simulation.world.rules.zoneGrowthIntervalDays * 2 - 1)
        let grown = simulation.world.buildings.filter { $0.category == .housing }.count - houses
        #expect(grown >= 1)
        let empty = simulation.world.buildings.filter { $0.category == .housing && $0.residents == 0 }.count
        #expect(empty <= 1)
    }

    @Test func noGrowthWithoutDemand() throws {
        // No open jobs and no stored food.
        var simulation = try zonedSimulation { $0.startingStock = [] }
        let houses = simulation.world.buildings.filter { $0.category == .housing }.count
        simulation.advance(days: simulation.world.rules.zoneGrowthIntervalDays)
        #expect(simulation.world.buildings.filter { $0.category == .housing }.count == houses)
    }

    @Test func noGrowthWithoutRoad() throws {
        var simulation = try Fixtures.flatSimulation()
        simulation.execute(ZoneCommand(cells: ZonePlanner.rectangle(from: GridPoint(x: 2, z: 2), to: GridPoint(x: 6, z: 6)), kind: .residential))
        for x in 13...19 {
            try simulation.place("grainFarm", x: x, z: 20)
        }
        let houses = simulation.world.buildings.filter { $0.category == .housing }.count
        simulation.advance(days: simulation.world.rules.zoneGrowthIntervalDays)
        #expect(simulation.world.buildings.filter { $0.category == .housing }.count == houses)
    }
}
