import GameDomain
@testable import GameSimulation
import Testing

@Suite("Roads")
struct RoadTests {
    @Test func pathIsLShapedAndConnected() {
        let path = RoadPlanner.path(from: GridPoint(x: 0, z: 0), to: GridPoint(x: 3, z: -2))
        #expect(path.first == GridPoint(x: 0, z: 0))
        #expect(path.last == GridPoint(x: 3, z: -2))
        #expect(path.count == 6)
        for (a, b) in zip(path, path.dropFirst()) {
            #expect(abs(a.x - b.x) + abs(a.z - b.z) == 1)
        }
    }

    @Test func singleCellPath() {
        #expect(RoadPlanner.path(from: GridPoint(x: 2, z: 2), to: GridPoint(x: 2, z: 2)) == [GridPoint(x: 2, z: 2)])
    }

    @Test func buildingARoadCostsMoney() throws {
        var simulation = try Fixtures.flatSimulation(settlement: false)
        let start = simulation.world.treasury
        simulation.execute(BuildRoadCommand(cells: RoadPlanner.path(from: GridPoint(x: 1, z: 1), to: GridPoint(x: 5, z: 1))))
        #expect(simulation.world.roads.count == 5)
        #expect(simulation.world.treasury == start - 5 * simulation.world.rules.roadCostPerCell)
        #expect(simulation.lastEvent == .roadBuilt(cells: 5, cost: 5 * simulation.world.rules.roadCostPerCell))
    }

    @Test func existingRoadIsNotChargedAgain() throws {
        var simulation = try Fixtures.flatSimulation(settlement: false)
        simulation.execute(BuildRoadCommand(cells: [GridPoint(x: 1, z: 1), GridPoint(x: 2, z: 1)]))
        let afterFirst = simulation.world.treasury
        simulation.execute(BuildRoadCommand(cells: [GridPoint(x: 2, z: 1), GridPoint(x: 3, z: 1)]))
        #expect(simulation.world.treasury == afterFirst - simulation.world.rules.roadCostPerCell)
        #expect(simulation.world.roads.count == 3)
    }

    @Test func roadsAndBuildingsExcludeEachOther() throws {
        var simulation = try Fixtures.flatSimulation(settlement: false)
        try simulation.place("mill", x: 4, z: 4)
        simulation.execute(BuildRoadCommand(cells: [GridPoint(x: 4, z: 4)]))
        #expect(simulation.lastEvent == .placementRejected(.occupied))
        #expect(simulation.world.roads.isEmpty)

        simulation.execute(BuildRoadCommand(cells: [GridPoint(x: 6, z: 6)]))
        simulation.execute(PlaceBuildingCommand(buildingType: "house", cell: GridPoint(x: 6, z: 6)))
        #expect(simulation.lastEvent == .placementRejected(.occupied))
    }

    @Test func roadsSkipWaterAndInvalidCells() throws {
        let catalog = try Fixtures.catalog()
        let terrain = Terrain.flat(size: 16).replacingBiome(at: GridPoint(x: 2, z: 0), with: .water)
        var simulation = Simulation(world: WorldFactory.makeWorld(catalog: catalog, terrain: terrain, foundSettlement: false))
        simulation.execute(BuildRoadCommand(cells: RoadPlanner.path(from: GridPoint(x: 0, z: 0), to: GridPoint(x: 4, z: 0))))
        #expect(simulation.world.roads == [GridPoint(x: 0, z: 0), GridPoint(x: 1, z: 0), GridPoint(x: 3, z: 0), GridPoint(x: 4, z: 0)])

        simulation.execute(BuildRoadCommand(cells: [GridPoint(x: 2, z: 0)]))
        #expect(simulation.lastEvent == .placementRejected(.water))
    }

    @Test func notEnoughMoneyRejectsTheWholeRoad() throws {
        var simulation = try Fixtures.flatSimulation(size: 64, settlement: false) { $0.startingTreasury = 40 }
        simulation.execute(BuildRoadCommand(cells: RoadPlanner.path(from: GridPoint(x: 0, z: 0), to: GridPoint(x: 9, z: 0))))
        #expect(simulation.world.roads.isEmpty)
        #expect(simulation.lastEvent == .placementRejected(.insufficientFunds(cost: 10 * simulation.world.rules.roadCostPerCell)))
    }

    @Test func demolishingRefundsHalf() throws {
        var simulation = try Fixtures.flatSimulation(settlement: false)
        let cells = RoadPlanner.path(from: GridPoint(x: 1, z: 1), to: GridPoint(x: 4, z: 1))
        simulation.execute(BuildRoadCommand(cells: cells))
        let before = simulation.world.treasury
        simulation.execute(DemolishRoadCommand(cells: Array(cells.prefix(2))))
        #expect(simulation.world.roads.count == 2)
        #expect(simulation.world.treasury == before + 2 * simulation.world.rules.roadCostPerCell / 2)
    }
}
