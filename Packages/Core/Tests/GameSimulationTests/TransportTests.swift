import GameDomain
@testable import GameSimulation
import Testing

@Suite("Transport lines")
struct TransportTests {
    /// 64 × 64 map with the settlement at (32, 32). A grain farm in the west and a mill
    /// in the east are 450 m apart, far beyond carrier range. Each has a stop next to it;
    /// a road along z = 20 connects the stops.
    private func corridor(withLine: Bool, carts: Int = 1) throws -> (simulation: Simulation, mill: BuildingID) {
        var simulation = try Fixtures.flatSimulation(size: 64)
        simulation.execute(BuildRoadCommand(cells: RoadPlanner.path(from: GridPoint(x: 5, z: 20), to: GridPoint(x: 59, z: 20))))
        try simulation.place("grainFarm", x: 4, z: 19)
        try simulation.place("stop", x: 5, z: 19)
        try simulation.place("stop", x: 59, z: 19)
        try simulation.placeZoned("mill", x: 60, z: 19)

        let stops = simulation.world.buildings.filter { $0.category == .stop }.map(\.id)
        if withLine {
            simulation.execute(CreateLineCommand(stops: stops))
            let line = try #require(simulation.world.lines.first)
            for _ in 0..<carts {
                simulation.execute(BuyVehicleCommand(lineID: line.id, vehicleType: "oxCart"))
            }
        }
        let mill = try #require(simulation.world.building(at: GridPoint(x: 60, z: 19)))
        return (simulation, mill.id)
    }

    private func grainReached(_ mill: BuildingID, in simulation: Simulation) -> Bool {
        guard let building = simulation.world.building(mill) else { return false }
        return building.input.count(of: "grain") > 0 || building.output.count(of: "flour") > 0 || building.isCycleRunning
    }

    @Test func roadPathFollowsTheRoad() {
        let roads = Set(RoadPlanner.path(from: GridPoint(x: 0, z: 1), to: GridPoint(x: 5, z: 1)))
        let path = RoadNetwork.path(from: GridPoint(x: 0, z: 0), to: GridPoint(x: 5, z: 0), roads: roads)
        #expect(path?.first == GridPoint(x: 0, z: 1))
        #expect(path?.last == GridPoint(x: 5, z: 1))
        #expect(path?.count == 6)
    }

    @Test func noPathWithoutConnection() {
        let roads: Set<GridPoint> = [GridPoint(x: 0, z: 1), GridPoint(x: 5, z: 1)]
        #expect(RoadNetwork.path(from: GridPoint(x: 0, z: 0), to: GridPoint(x: 5, z: 0), roads: roads) == nil)
    }

    @Test func routePointsAreInterpolated() {
        let points = [WorldPoint(x: 0, z: 0), WorldPoint(x: 10, z: 0), WorldPoint(x: 10, z: 10)]
        #expect(Route.length(of: points) == 20)
        #expect(Route.point(on: points, at: 15) == WorldPoint(x: 10, z: 5))
        #expect(Route.point(on: points, at: 99) == WorldPoint(x: 10, z: 10))
    }

    @Test func stopsNeedRoadAccess() throws {
        var simulation = try Fixtures.flatSimulation(settlement: false)
        simulation.execute(PlaceBuildingCommand(buildingType: "stop", cell: GridPoint(x: 4, z: 4)))
        #expect(simulation.lastEvent == .placementRejected(.noRoadAccess))
        simulation.execute(BuildRoadCommand(cells: [GridPoint(x: 4, z: 5)]))
        try simulation.place("stop", x: 4, z: 4)
    }

    @Test func lineNeedsTwoStops() throws {
        var simulation = try Fixtures.flatSimulation(settlement: false)
        simulation.execute(BuildRoadCommand(cells: [GridPoint(x: 4, z: 5)]))
        try simulation.place("stop", x: 4, z: 4)
        let stop = try #require(simulation.world.building(at: GridPoint(x: 4, z: 4)))
        simulation.execute(CreateLineCommand(stops: [stop.id, stop.id]))
        #expect(simulation.lastEvent == .lineRejected)
        #expect(simulation.world.lines.isEmpty)
    }

    @Test func carriersDoNotCoverLongDistances() throws {
        var (simulation, mill) = try corridor(withLine: false)
        simulation.advance(days: 30)
        #expect(!grainReached(mill, in: simulation))
    }

    @Test func oxCartsBringGrainAlongTheLine() throws {
        var (simulation, mill) = try corridor(withLine: true)
        simulation.advance(days: 30)
        #expect(grainReached(mill, in: simulation))
        #expect(simulation.world.vehicles.count == 1)
    }

    @Test func vehiclesCostMoneyAndUpkeep() throws {
        var (simulation, _) = try corridor(withLine: true, carts: 2)
        let vehicles = simulation.world.ledger.account(forYear: 0).total(for: .vehicles)
        #expect(vehicles == -800)

        simulation.advance(days: simulation.world.rules.daysPerYear)
        #expect(simulation.world.ledger.account(forYear: 0).total(for: .vehicles) == -800 - 160)
    }

    @Test func demolishingAStopShortensTheLine() throws {
        var (simulation, _) = try corridor(withLine: true)
        let stop = try #require(simulation.world.building(at: GridPoint(x: 59, z: 19)))
        simulation.execute(DemolishBuildingCommand(buildingID: stop.id))
        #expect(simulation.world.lines.first?.stops.count == 1)
        simulation.advance(days: 2)
        #expect(simulation.world.vehicles.first?.status == .idle)
    }

    @Test func sellingAndDeletingRefundHalf() throws {
        var (simulation, _) = try corridor(withLine: true, carts: 2)
        let line = try #require(simulation.world.lines.first)
        let before = simulation.world.treasury
        simulation.execute(SellVehicleCommand(lineID: line.id))
        #expect(simulation.world.treasury == before + 200)
        simulation.execute(DeleteLineCommand(lineID: line.id))
        #expect(simulation.world.treasury == before + 400)
        #expect(simulation.world.lines.isEmpty)
        #expect(simulation.world.vehicles.isEmpty)
    }
}
