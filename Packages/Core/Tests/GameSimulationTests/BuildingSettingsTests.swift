import GameDomain
@testable import GameSimulation
import Testing

@Suite("Building settings")
struct BuildingSettingsTests {
    @Test func pausedBuildingsReleaseWorkersAndStop() throws {
        var simulation = try Fixtures.flatSimulation()
        try simulation.place("grainFarm", x: 15, z: 16)
        let farm = try #require(simulation.world.building(at: GridPoint(x: 15, z: 16)))
        #expect(simulation.world.building(farm.id)?.assignedWorkers == 6)

        simulation.execute(ConfigureBuildingCommand(buildingID: farm.id, isPaused: true))
        simulation.advance(days: 10)
        let paused = try #require(simulation.world.building(farm.id))
        #expect(paused.assignedWorkers == 0)
        #expect(paused.status == .paused)
        #expect(simulation.world.goodsStatistics.flow(of: "grain", year: 0).produced == 0)

        simulation.execute(ConfigureBuildingCommand(buildingID: farm.id, isPaused: false))
        #expect(simulation.world.building(farm.id)?.assignedWorkers == 6)
    }

    @Test func pausedBuildingsReceiveNoDeliveries() throws {
        var simulation = try Fixtures.flatSimulation()
        try simulation.place("grainFarm", x: 15, z: 16)
        try simulation.placeZoned("mill", x: 17, z: 16)
        let mill = try #require(simulation.world.building(at: GridPoint(x: 17, z: 16)))
        simulation.execute(ConfigureBuildingCommand(buildingID: mill.id, isPaused: true))
        simulation.advance(days: 20)
        #expect(simulation.world.building(mill.id)?.input.count(of: "grain") == 0)
        #expect(simulation.world.storedAmount(of: "grain") > 0)
    }

    @Test func highPriorityIsServedFirst() throws {
        var simulation = try Fixtures.flatSimulation(settlement: false)
        try simulation.place("grainFarm", x: 16, z: 10)
        try simulation.placeZoned("mill", x: 14, z: 10)
        try simulation.placeZoned("mill", x: 18, z: 10)
        let farm = try #require(simulation.world.building(at: GridPoint(x: 16, z: 10)))
        let first = try #require(simulation.world.building(at: GridPoint(x: 14, z: 10)))
        let second = try #require(simulation.world.building(at: GridPoint(x: 18, z: 10)))
        let planner = NearestConsumerPlanner()

        // Same distance: the older mill wins.
        #expect(planner.target(for: "grain", from: farm, in: simulation.world)?.buildingID == first.id)

        simulation.execute(ConfigureBuildingCommand(buildingID: second.id, priority: .high))
        #expect(planner.target(for: "grain", from: farm, in: simulation.world)?.buildingID == second.id)

        simulation.execute(ConfigureBuildingCommand(buildingID: second.id, priority: .low))
        simulation.execute(ConfigureBuildingCommand(buildingID: first.id, priority: .low))
        #expect(planner.target(for: "grain", from: farm, in: simulation.world)?.buildingID == first.id)
    }

    @Test func housesCannotBePaused() throws {
        var simulation = try Fixtures.flatSimulation()
        let house = try #require(simulation.world.buildings.first { $0.category == .housing })
        simulation.execute(ConfigureBuildingCommand(buildingID: house.id, isPaused: true))
        #expect(simulation.world.building(house.id)?.isPaused == false)
    }
}
