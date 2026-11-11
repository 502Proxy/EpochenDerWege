import GameData
import GameDomain
@testable import GameSimulation
import Testing

@Suite("Settlement levels")
struct SettlementLevelTests {
    @Test func catalogDefinesAscendingLevels() throws {
        let catalog = try Fixtures.catalog()
        #expect(catalog.settlementLevels.count >= 3)
        #expect(catalog.settlementLevels.first?.minimumPopulation == 0)
        #expect(catalog.settlementLevel(forPopulation: 0) == 0)
        let village = catalog.settlementLevels[1].minimumPopulation
        #expect(catalog.settlementLevel(forPopulation: village - 1) == 0)
        #expect(catalog.settlementLevel(forPopulation: village) == 1)
    }

    @Test func startsAsHamletAndLevelsUpWithPopulation() throws {
        var simulation = try Fixtures.flatSimulation()
        #expect(simulation.world.settlementLevel == 0)

        var world = simulation.world
        let houses = world.buildings.indices.filter { world.buildings[$0].category == .housing }
        let target = world.catalog.settlementLevels[1].minimumPopulation
        for (offset, index) in houses.enumerated() {
            world.buildings[index].residents = target / houses.count + (offset == 0 ? target % houses.count : 0)
        }
        SettlementSystem.updateLevel(in: &world)

        #expect(world.settlementLevel == 1)
        #expect(world.events.last?.event == .settlementLevelReached(1))
        simulation = Simulation(world: world)
        #expect(simulation.world.settlementLevel == 1)
    }

    @Test func levelsAreKeptWhenResidentsLeave() throws {
        var world = try Fixtures.flatSimulation().world
        world.settlementLevel = 2
        SettlementSystem.updateLevel(in: &world)
        #expect(world.settlementLevel == 2)
    }

    @Test func lockedBuildingsCannotBePlaced() throws {
        let catalog = try Fixtures.catalog()
        var mill = try #require(catalog.building("mill"))
        mill.allowedZones = nil
        mill.requiredLevel = 1
        let world = WorldFactory.makeWorld(catalog: catalog, terrain: .flat(size: 16), foundSettlement: false)
        #expect((try? PlacementValidator.validate(mill, at: GridPoint(x: 4, z: 4), in: world).get()) == nil)
        if case .failure(let error) = PlacementValidator.validate(mill, at: GridPoint(x: 4, z: 4), in: world) {
            #expect(error == .requiresLevel(1))
        }

        var unlocked = world
        unlocked.settlementLevel = 1
        #expect((try? PlacementValidator.validate(mill, at: GridPoint(x: 4, z: 4), in: unlocked).get()) != nil)
    }

    @Test func validatorRejectsUnorderedLevels() throws {
        let catalog = try Fixtures.catalog()
        let broken = GameCatalog(
            rules: catalog.rules,
            goods: catalog.goods,
            buildings: catalog.buildings,
            vehicles: catalog.vehicles,
            settlementLevels: [
                SettlementLevel(id: "a", name: "A", minimumPopulation: 0),
                SettlementLevel(id: "b", name: "B", minimumPopulation: 0),
            ]
        )
        #expect(throws: GameDataError.self) { try CatalogValidator.validate(broken) }
    }
}

@Suite("Zone demand")
struct ZoneDemandTests {
    @Test func openJobsCreateResidentialDemand() throws {
        var simulation = try Fixtures.flatSimulation()
        for x in 13...19 {
            try simulation.place("grainFarm", x: x, z: 20)
        }
        let demand = ZoneDemand.compute(for: .residential, in: simulation.world)
        #expect(demand.isGrowing)
        if case .openJobs(let jobs) = demand.reason {
            #expect(jobs > 0)
        } else {
            Issue.record("Expected open jobs, got \(demand.reason)")
        }
        // Nothing is zoned yet, so there is nowhere to build.
        #expect(demand.lacksSpace)
    }

    @Test func noFoodMeansNoResidentialDemand() throws {
        let simulation = try Fixtures.flatSimulation { $0.startingStock = [] }
        let demand = ZoneDemand.compute(for: .residential, in: simulation.world)
        #expect(!demand.isGrowing)
        #expect(!demand.lacksSpace)
    }

    @Test func demandMatchesWhatTheTownBuilds() throws {
        var simulation = try Fixtures.flatSimulation()
        simulation.execute(BuildRoadCommand(cells: RoadPlanner.path(from: GridPoint(x: 8, z: 10), to: GridPoint(x: 24, z: 10))))
        simulation.execute(ZoneCommand(cells: ZonePlanner.rectangle(from: GridPoint(x: 8, z: 8), to: GridPoint(x: 24, z: 9)), kind: .residential))
        for x in 13...19 {
            try simulation.place("grainFarm", x: x, z: 20)
        }
        let demand = ZoneDemand.compute(for: .residential, in: simulation.world)
        #expect(demand.isGrowing)
        #expect(!demand.lacksSpace)

        let houses = simulation.world.buildings.filter { $0.category == .housing }.count
        simulation.advance(days: simulation.world.rules.zoneGrowthIntervalDays)
        #expect(simulation.world.buildings.filter { $0.category == .housing }.count == houses + 1)

        // The new house is empty, so demand drops below the threshold until it is moved into.
        let afterwards = ZoneDemand.compute(for: .residential, in: simulation.world)
        if simulation.world.buildings.contains(where: { $0.category == .housing && $0.residents == 0 }) {
            #expect(afterwards.reason == .waitingForResidents)
            #expect(!afterwards.isGrowing)
        }
    }

    @Test func commercialDemandFollowsPopulation() throws {
        let world = try Fixtures.flatSimulation().world
        let market = try #require(world.catalog.building("market"))
        let perMarket = try #require(market.residentsPerBuilding)
        let demand = ZoneDemand.compute(for: .commercial, in: world)
        #expect(demand.isGrowing == (world.population / perMarket > 0))
        #expect(demand.value > 0)
    }
}
