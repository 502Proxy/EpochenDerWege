import GameData
import GameDomain
@testable import GameSimulation
import Testing

/// Shared fixtures.
enum Fixtures {
    static func catalog() throws -> GameCatalog {
        try BundledCatalogRepository().loadCatalog()
    }

    /// A flat grass map with the starting settlement in the middle (cell 16, 16).
    static func flatSimulation(size: Int = 32, settlement: Bool = true, rules: ((inout GameRules) -> Void)? = nil) throws -> Simulation {
        var catalog = try catalog()
        if let rules {
            var modified = catalog.rules
            rules(&modified)
            catalog = catalog.replacingRules(modified)
        }
        let world = WorldFactory.makeWorld(catalog: catalog, terrain: .flat(size: size), foundSettlement: settlement)
        return Simulation(world: world)
    }
}

extension Simulation {
    /// Places a building through the regular command path and fails the test if it was rejected.
    mutating func place(_ type: BuildingTypeID, x: Int, z: Int) throws {
        let before = world.buildings.count
        execute(PlaceBuildingCommand(buildingType: type, cell: GridPoint(x: x, z: z)))
        try #require(world.buildings.count == before + 1, "Placing \(type) at \(x), \(z) was rejected")
    }

    var lastEvent: SimulationEvent? {
        world.events.last?.event
    }
}

@Suite("World generation")
struct WorldGenerationTests {
    @Test func sameSeedGivesSameTerrain() {
        let a = TerrainGenerator(seed: 42, size: 64).generate()
        let b = TerrainGenerator(seed: 42, size: 64).generate()
        for z in 0...64 {
            for x in 0...64 {
                #expect(a.cornerHeight(x: x, z: z) == b.cornerHeight(x: x, z: z))
            }
        }
    }

    @Test func defaultSeedHasVariedBiomes() {
        let terrain = TerrainGenerator(seed: 2026).generate()
        var biomes = Set<Biome>()
        for z in 0..<terrain.size {
            for x in 0..<terrain.size {
                biomes.insert(terrain.biome(at: GridPoint(x: x, z: z)))
            }
        }
        #expect(biomes.isSuperset(of: [.water, .grass, .forest, .rock]))
    }

    @Test(arguments: [UInt64(1), 7, 42, 99, 2026])
    func everySeedFindsAStart(seed: UInt64) throws {
        let world = WorldFactory.makeWorld(catalog: try Fixtures.catalog(), seed: seed)
        #expect(world.startCell != nil)
        #expect(world.population == 20)
    }

    @Test func startingSettlement() throws {
        let simulation = try Fixtures.flatSimulation()
        let world = simulation.world
        let rules = world.rules
        #expect(world.startCell == GridPoint(x: 16, z: 16))
        #expect(world.buildings.filter { $0.category == .storage }.count == 1)
        #expect(world.buildings.filter { $0.category == .housing }.count == rules.startingHouses)
        #expect(world.population == rules.startingHouses * rules.startingResidentsPerHouse)
        #expect(world.storedAmount(of: "bread") == 30)
    }
}

@Suite("Placement")
struct PlacementTests {
    @Test func rejectsWaterOccupiedAndMissingResources() throws {
        let catalog = try Fixtures.catalog()
        let terrain = Terrain.flat(size: 16).replacingBiome(at: GridPoint(x: 0, z: 0), with: .water)
        var simulation = Simulation(world: WorldFactory.makeWorld(catalog: catalog, terrain: terrain, foundSettlement: false))

        simulation.execute(PlaceBuildingCommand(buildingType: "house", cell: GridPoint(x: 0, z: 0)))
        #expect(simulation.lastEvent == .placementRejected(.water))

        try simulation.place("house", x: 5, z: 5)
        simulation.execute(PlaceBuildingCommand(buildingType: "mill", cell: GridPoint(x: 5, z: 5)))
        #expect(simulation.lastEvent == .placementRejected(.occupied))

        simulation.execute(PlaceBuildingCommand(buildingType: "woodcutter", cell: GridPoint(x: 8, z: 8)))
        #expect(simulation.lastEvent == .placementRejected(.missingResource(.forest)))

        simulation.execute(PlaceBuildingCommand(buildingType: "castle", cell: GridPoint(x: 9, z: 9)))
        #expect(simulation.lastEvent == .placementRejected(.unknownBuildingType("castle")))
    }

    @Test func costsMoneyAndRefundsHalfOnDemolition() throws {
        var simulation = try Fixtures.flatSimulation(settlement: false)
        let start = simulation.world.treasury
        try simulation.place("mill", x: 4, z: 4)
        #expect(simulation.world.treasury == start - 600)

        let mill = try #require(simulation.world.building(at: GridPoint(x: 4, z: 4)))
        simulation.execute(DemolishBuildingCommand(buildingID: mill.id))
        #expect(simulation.world.treasury == start - 300)
        #expect(simulation.world.building(at: GridPoint(x: 4, z: 4)) == nil)
        #expect(simulation.lastEvent == .buildingDemolished("mill", refund: 300))
    }

    @Test func runsOutOfMoney() throws {
        var simulation = try Fixtures.flatSimulation(size: 16, settlement: false)
        for index in 0..<40 {
            simulation.execute(PlaceBuildingCommand(buildingType: "storehouse", cell: GridPoint(x: index % 16, z: index / 16 + 2)))
        }
        let storehouses = simulation.world.buildings.count
        #expect(storehouses == simulation.world.rules.startingTreasury / 800)
        #expect(simulation.lastEvent == .placementRejected(.insufficientFunds(cost: 800)))
    }

    @Test func validatorIsUsableOnSnapshots() throws {
        let simulation = try Fixtures.flatSimulation()
        let world = simulation.world
        let mill = try #require(world.catalog.building("mill"))
        let start = try #require(world.startCell)
        #expect((try? PlacementValidator.validate(mill, at: start, in: world).get()) == nil)
        #expect((try? PlacementValidator.validate(mill, at: start.offset(dx: 1, dz: 0), in: world).get()) == 1)
    }
}

@Suite("Economy loop")
struct EconomyLoopTests {
    @Test func oneFarmFeedsTheStartingSettlementFairly() throws {
        var simulation = try Fixtures.flatSimulation()
        try simulation.place("grainFarm", x: 15, z: 16)
        try simulation.place("mill", x: 17, z: 16)
        try simulation.place("bakery", x: 16, z: 17)

        simulation.advance(days: 60)

        let world = simulation.world
        #expect(world.buildings.filter { $0.category == .housing }.allSatisfy { $0.residents > 0 })
        #expect(world.population == world.rules.startingHouses * world.rules.startingResidentsPerHouse)
    }

    @Test func twoFarmsProduceABreadSurplus() throws {
        var simulation = try Fixtures.flatSimulation()
        try simulation.place("grainFarm", x: 15, z: 16)
        try simulation.place("grainFarm", x: 15, z: 15)
        try simulation.place("mill", x: 17, z: 16)
        try simulation.place("bakery", x: 16, z: 17)

        simulation.advance(days: 60)

        #expect(simulation.world.storedAmount(of: "bread") > 0)
    }

    @Test func housesShrinkWithoutFood() throws {
        var simulation = try Fixtures.flatSimulation { $0.startingStock = [] }
        let before = simulation.world.population
        simulation.advance(days: simulation.world.rules.supplyCheckIntervalDays * 2)
        #expect(simulation.world.population == before - 10)
    }

    @Test func unusedGoodsGoToTheStorehouse() throws {
        var simulation = try Fixtures.flatSimulation()
        try simulation.place("grainFarm", x: 17, z: 17)
        simulation.advance(days: 30)
        #expect(simulation.world.storedAmount(of: "grain") > 0)
    }

    @Test func yearlyTaxesAndUpkeep() throws {
        var simulation = try Fixtures.flatSimulation {
            $0.startingStock = [GoodAmount(good: "bread", amount: 200)]
            $0.taxPerResidentPerYear = 5
        }
        let start = simulation.world.treasury
        simulation.advance(days: simulation.world.rules.daysPerYear)

        #expect(simulation.world.clock.year == 1)
        #expect(simulation.world.treasury == start + 20 * 5 - 20)
        #expect(simulation.world.events.contains { $0.event == .yearClosed(year: 1, taxes: 100, upkeep: 20) })
    }

    @Test func demolishingATargetTurnsCarriersBack() throws {
        var simulation = try Fixtures.flatSimulation()
        try simulation.place("grainFarm", x: 17, z: 17)
        simulation.advance(days: 10)
        let storehouse = try #require(simulation.world.building(at: GridPoint(x: 16, z: 16)))

        simulation.execute(DemolishBuildingCommand(buildingID: storehouse.id))
        simulation.advance(days: 5)

        #expect(simulation.world.carriers.allSatisfy { $0.targetID != storehouse.id || $0.phase == .returning })
    }

    @Test func simulationIsDeterministic() throws {
        func run() throws -> (treasury: Int, population: Int, stock: [GoodAmount]) {
            var simulation = Simulation(world: WorldFactory.makeWorld(catalog: try Fixtures.catalog(), seed: 7))
            let start = try #require(simulation.world.startCell)
            simulation.execute(PlaceBuildingCommand(buildingType: "grainFarm", cell: start.offset(dx: 1, dz: 0)))
            simulation.execute(PlaceBuildingCommand(buildingType: "mill", cell: start.offset(dx: -1, dz: 0)))
            simulation.advance(days: 90)
            return (simulation.world.treasury, simulation.world.population, simulation.world.storedGoods)
        }
        let first = try run()
        let second = try run()
        #expect(first.treasury == second.treasury)
        #expect(first.population == second.population)
        #expect(first.stock == second.stock)
    }
}

@Suite("Engine")
struct EngineTests {
    @Test func runsTicksAndAppliesCommandsInTheBackground() async throws {
        let simulation = try Fixtures.flatSimulation()
        let engine = SimulationEngine(simulation: simulation)
        engine.setSpeed(4)
        engine.start()
        engine.submit(PlaceBuildingCommand(buildingType: "mill", cell: GridPoint(x: 17, z: 16)))

        try await Task.sleep(for: .milliseconds(400))
        engine.stop()

        let frame = engine.snapshots.value
        #expect(frame.world.clock.tick > 0)
        #expect(frame.world.building(at: GridPoint(x: 17, z: 16))?.definition.id == "mill")
    }

    @Test func pauseStopsTimeButNotCommands() async throws {
        let engine = SimulationEngine(simulation: try Fixtures.flatSimulation())
        engine.setSpeed(0)
        engine.start()
        engine.submit(PlaceBuildingCommand(buildingType: "mill", cell: GridPoint(x: 17, z: 16)))

        try await Task.sleep(for: .milliseconds(300))
        engine.stop()

        let frame = engine.snapshots.value
        #expect(frame.world.clock.tick == 0)
        #expect(frame.world.building(at: GridPoint(x: 17, z: 16)) != nil)
    }

    @Test func interpolationFractionIsClamped() throws {
        let world = try Fixtures.flatSimulation().world
        let now = ContinuousClock.now
        let frame = SimulationFrame(world: world, previous: world, publishedAt: now, tickInterval: .milliseconds(100))
        #expect(frame.interpolationFraction(at: now) == 0)
        #expect(abs(frame.interpolationFraction(at: now + .milliseconds(50)) - 0.5) < 0.0001)
        #expect(frame.interpolationFraction(at: now + .seconds(1)) == 1)
    }
}
