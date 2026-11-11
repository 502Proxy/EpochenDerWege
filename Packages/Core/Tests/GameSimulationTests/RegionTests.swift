import GameData
import GameDomain
@testable import GameSimulation
import Testing

@Suite("Region: deposits and neighbouring towns")
struct RegionTests {
    /// A flat 128 × 128 map: large enough for deposits and towns around the start.
    private func regionWorld() throws -> WorldState {
        WorldFactory.makeWorld(catalog: try Fixtures.catalog(), terrain: .flat(size: 128))
    }

    private func cellDistance(_ a: GridPoint, _ b: GridPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dz = Double(a.z - b.z)
        return (dx * dx + dz * dz).squareRoot()
    }

    @Test(arguments: [UInt64(7), 2026])
    func depositsLieBeyondCarrierRange(seed: UInt64) throws {
        let world = WorldFactory.makeWorld(catalog: try Fixtures.catalog(), seed: seed)
        let start = try #require(world.startCell)
        let rangeInCells = world.rules.carrierRangeMeters / world.terrain.cellSize
        var found = Set<Deposit>()
        for z in 0..<world.terrain.size {
            for x in 0..<world.terrain.size {
                let cell = GridPoint(x: x, z: z)
                guard let deposit = world.terrain.deposit(at: cell) else { continue }
                found.insert(deposit)
                #expect(cellDistance(cell, start) > rangeInCells)
            }
        }
        #expect(found == Set(Deposit.allCases))
    }

    @Test func townsAreFoundedFarAwayWithTheirOwnStop() throws {
        let world = try regionWorld()
        let start = try #require(world.startCell)
        #expect(!world.towns.isEmpty)
        for town in world.towns {
            #expect(cellDistance(town.center, start) >= Double(RegionPlanner.townDistance.lowerBound))
            let stop = try #require(world.building(town.stopID))
            #expect(stop.category == .stop)
            #expect(stop.townID == town.id)
            #expect(world.town(owningStop: stop.id)?.id == town.id)
            #expect(world.hasRoad(at: town.center))
        }
        // Towns do not count as the player's population.
        #expect(world.population == world.rules.startingHouses * world.rules.startingResidentsPerHouse)
    }

    @Test func nothingCanBeBuiltInATown() throws {
        var simulation = Simulation(world: try regionWorld())
        let town = try #require(simulation.world.towns.first)
        let cell = try #require(town.footprint.first)
        simulation.execute(PlaceBuildingCommand(buildingType: "woodcutter", cell: cell))
        #expect(simulation.lastEvent == .placementRejected(.occupied))

        let stops = simulation.world.buildings.filter { $0.category == .stop }.count
        simulation.execute(DemolishBuildingCommand(buildingID: town.stopID))
        #expect(simulation.world.buildings.filter { $0.category == .stop }.count == stops)
    }

    @Test func quarriesNeedAStoneDeposit() throws {
        var simulation = Simulation(world: try regionWorld())
        let start = try #require(simulation.world.startCell)
        // Right next to the storehouse: free, flat, but far from any deposit.
        simulation.execute(PlaceBuildingCommand(buildingType: "quarry", cell: start.offset(dx: 1, dz: 0)))
        #expect(simulation.lastEvent == .placementRejected(.missingDeposit(.stone)))

        let terrain = simulation.world.terrain
        var stoneCell: GridPoint?
        search: for z in 0..<terrain.size {
            for x in 0..<terrain.size where terrain.deposit(at: GridPoint(x: x, z: z)) == .stone {
                let cell = GridPoint(x: x, z: z)
                if case .success = PlacementValidator.validate(try #require(simulation.world.catalog.building("quarry")), at: cell, in: simulation.world) {
                    stoneCell = cell
                    break search
                }
            }
        }
        let cell = try #require(stoneCell)
        try simulation.place("quarry", x: cell.x, z: cell.z)
    }

    @Test func townsOfferTheirGoodsEveryTradePeriod() throws {
        var simulation = Simulation(world: try regionWorld())
        let town = try #require(simulation.world.towns.first)
        let offer = try #require(town.template.sells.first)
        simulation.advance(days: simulation.world.rules.tradeIntervalDays)
        let stop = try #require(simulation.world.building(town.stopID))
        #expect(stop.output.count(of: offer.good) >= offer.amount)
    }

    @Test func vehiclesSellToTownsAtAPremiumAndBuyAtBasePrice() throws {
        var world = try regionWorld()
        // A town selling something the starting village can use, and who uses it.
        let consumers: [GoodID: BuildingTypeID] = ["fish": "house", "stone": "workshop", "grain": "mill"]
        let townIndex = try #require(world.towns.indices.first { index in
            world.towns[index].template.sells.contains { consumers[$0.good] != nil }
        })
        let town = world.towns[townIndex]
        let offer = try #require(town.template.sells.first { consumers[$0.good] != nil })
        let wanted = try #require(town.template.buys.first)
        let stopIndex = try #require(world.index(of: town.stopID))
        world.buildings[stopIndex].output.add(offer.good, amount: offer.amount)

        let start = try #require(world.startCell)
        let stopDefinition = try #require(world.catalog.firstBuilding(of: .stop))
        let playerStop = world.addBuilding(stopDefinition, at: start.offset(dx: 3, dz: -3), resourceFactor: 1)
        let consumer = try #require(consumers[offer.good].flatMap { world.catalog.building($0) })
        world.addBuilding(consumer, at: start.offset(dx: 4, dz: -3), resourceFactor: 1)

        let definition = try #require(world.catalog.vehicles.first)
        var vehicle = Vehicle(id: VehicleID(1), definition: definition, lineID: LineID(1), position: world.terrain.center(of: town.center))
        vehicle.cargo[wanted.good] = 1

        let before = world.treasury
        TradeSystem.trade(&vehicle, withTown: town.id, atBuildingIndex: stopIndex, otherStops: [playerStop], world: &world)

        let salePrice = Int((Double(world.catalog.good(wanted.good)?.basePrice ?? 0) * world.rules.townPriceFactor).rounded())
        let loaded = vehicle.cargo[offer.good, default: 0]
        let purchase = loaded * (world.catalog.good(offer.good)?.basePrice ?? 0)
        #expect(vehicle.cargo[wanted.good] == nil)
        #expect(world.towns[townIndex].wanted[wanted.good] == wanted.amount - 1)
        #expect(loaded > 0)
        #expect(world.treasury == before + salePrice - purchase)
    }
}
