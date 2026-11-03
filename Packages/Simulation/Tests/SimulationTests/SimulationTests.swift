import XCTest
@testable import Simulation

final class GameDataTests: XCTestCase {
    func testDefaultDataLoads() throws {
        let data = try GameData.loadDefault()
        XCTAssertEqual(data.rules.ticksPerDay, 20)
        XCTAssertNotNil(data.building("baeckerei"))
        XCTAssertNotNil(data.good("brot"))
    }

    func testAllReferencedGoodsExist() throws {
        let data = try GameData.loadDefault()
        for building in data.buildings {
            for good in building.inputs.keys {
                XCTAssertNotNil(data.good(good), "\(building.id) braucht unbekannte Ware \(good)")
            }
            for good in building.outputs.keys {
                XCTAssertNotNil(data.good(good), "\(building.id) erzeugt unbekannte Ware \(good)")
            }
        }
        for good in data.rules.foodGoods + Array(data.rules.startStock.keys) {
            XCTAssertNotNil(data.good(good), "Regeln nennen unbekannte Ware \(good)")
        }
    }
}

final class TerrainTests: XCTestCase {
    func testSameSeedGivesSameMap() {
        let a = Terrain(seed: 42, size: 64)
        let b = Terrain(seed: 42, size: 64)
        XCTAssertEqual(a.heights, b.heights)
        XCTAssertEqual(a.biomes, b.biomes)
    }

    func testDifferentSeedsGiveDifferentMaps() {
        let a = Terrain(seed: 1, size: 64)
        let b = Terrain(seed: 2, size: 64)
        XCTAssertNotEqual(a.heights, b.heights)
    }

    func testGeneratedMapHasVariedBiomes() {
        let terrain = Terrain(seed: 2026)
        let kinds = Set(terrain.biomes)
        XCTAssertTrue(kinds.contains(.grass))
        XCTAssertTrue(kinds.contains(.forest))
        XCTAssertGreaterThanOrEqual(kinds.count, 4)
    }

    func testHeightInterpolation() {
        let terrain = Terrain(flatSize: 8, height: 12)
        XCTAssertEqual(terrain.height(at: WorldPoint(x: 13.7, z: 40.2)), 12, accuracy: 0.0001)
    }
}

final class SimulationTests: XCTestCase {
    private func flatSimulation(size: Int = 32, settlement: Bool = true) throws -> Simulation {
        let data = try GameData.loadDefault()
        return Simulation(data: data, terrain: Terrain(flatSize: size), foundSettlement: settlement)
    }

    func testStartSettlementIsFounded() throws {
        let sim = try flatSimulation()
        let rules = sim.rules
        XCTAssertNotNil(sim.startCell)
        XCTAssertEqual(sim.buildings.filter { $0.definition.category == .storage }.count, 1)
        XCTAssertEqual(sim.buildings.filter { $0.definition.category == .housing }.count, rules.startHouses)
        XCTAssertEqual(sim.population, rules.startHouses * rules.startResidentsPerHouse)
        XCTAssertEqual(sim.storedGoods["brot"], rules.startStock["brot"])
    }

    func testGeneratedMapFindsStart() throws {
        let data = try GameData.loadDefault()
        let sim = Simulation(data: data, seed: 2026)
        XCTAssertNotNil(sim.startCell)
        XCTAssertGreaterThan(sim.population, 0)
    }

    func testPlacementRules() throws {
        var terrain = Terrain(flatSize: 16)
        terrain.setBiome(.water, at: GridPoint(x: 0, z: 0))
        let sim = Simulation(data: try GameData.loadDefault(), terrain: terrain, foundSettlement: false)

        XCTAssertEqual(try? sim.place("haus", at: GridPoint(x: 0, z: 0)).get().id, nil)
        if case .failure(let error) = sim.place("haus", at: GridPoint(x: 0, z: 0)) {
            XCTAssertEqual(error, .water)
        } else {
            XCTFail("Bauen auf Wasser muss scheitern")
        }

        XCTAssertNoThrow(try sim.place("haus", at: GridPoint(x: 5, z: 5)).get())
        if case .failure(let error) = sim.place("muehle", at: GridPoint(x: 5, z: 5)) {
            XCTAssertEqual(error, .occupied)
        } else {
            XCTFail("Doppelt bauen muss scheitern")
        }

        // Kein Wald auf der flachen Graskarte → kein Holzfäller.
        if case .failure(let error) = sim.place("holzfaeller", at: GridPoint(x: 8, z: 8)) {
            XCTAssertEqual(error, .missingResource(.forest))
        } else {
            XCTFail("Holzfäller ohne Wald muss scheitern")
        }
    }

    func testPlacingCostsMoneyAndDemolishRefundsHalf() throws {
        let sim = try flatSimulation(settlement: false)
        let start = sim.money
        let mill = try sim.place("muehle", at: GridPoint(x: 4, z: 4)).get()
        XCTAssertEqual(sim.money, start - 600)
        sim.demolish(mill.id)
        XCTAssertEqual(sim.money, start - 300)
        XCTAssertNil(sim.building(at: GridPoint(x: 4, z: 4)))
    }

    func testNotEnoughMoney() throws {
        let sim = try flatSimulation(settlement: false)
        var placed = 0
        var lastError: PlacementError?
        for i in 0..<40 {
            switch sim.place("lager", at: GridPoint(x: i % 16, z: i / 16 + 2)) {
            case .success: placed += 1
            case .failure(let e): lastError = e
            }
        }
        XCTAssertEqual(placed, sim.rules.startMoney / 800)
        XCTAssertEqual(lastError, .notEnoughMoney(800))
    }

    func testBreadChainFeedsHouses() throws {
        let sim = try flatSimulation()
        guard let start = sim.startCell else { return XCTFail("Kein Start") }

        // Kette direkt neben dem Lager aufbauen.
        XCTAssertNoThrow(try sim.place("getreidehof", at: GridPoint(x: start.x - 1, z: start.z)).get())
        XCTAssertNoThrow(try sim.place("muehle", at: GridPoint(x: start.x + 1, z: start.z)).get())
        XCTAssertNoThrow(try sim.place("baeckerei", at: GridPoint(x: start.x, z: start.z + 1)).get())

        sim.advance(days: 60)

        let bakery = sim.buildings.first { $0.definition.id == "baeckerei" }!
        let mill = sim.buildings.first { $0.definition.id == "muehle" }!
        XCTAssertGreaterThan(mill.assignedWorkers, 0)
        XCTAssertGreaterThan(bakery.assignedWorkers, 0)

        // Ein Hof liefert knapp genug: Das Brot wird fair verteilt, niemand zieht weg.
        let houses = sim.buildings.filter { $0.definition.category == .housing }
        XCTAssertTrue(houses.allSatisfy { $0.residents > 0 }, "Häuser sind verhungert")
        XCTAssertEqual(sim.population, sim.rules.startHouses * sim.rules.startResidentsPerHouse)
    }

    func testTwoFarmsProduceBreadSurplus() throws {
        let sim = try flatSimulation()
        guard let start = sim.startCell else { return XCTFail("Kein Start") }
        _ = try sim.place("getreidehof", at: GridPoint(x: start.x - 1, z: start.z)).get()
        _ = try sim.place("getreidehof", at: GridPoint(x: start.x - 1, z: start.z - 1)).get()
        _ = try sim.place("muehle", at: GridPoint(x: start.x + 1, z: start.z)).get()
        _ = try sim.place("baeckerei", at: GridPoint(x: start.x, z: start.z + 1)).get()

        sim.advance(days: 60)

        // Überschuss landet im Lager.
        XCTAssertGreaterThan(sim.storedGoods["brot", default: 0], 0)
    }

    func testHousesShrinkWithoutFood() throws {
        let data = try GameData.loadDefault()
        var rules = data.rules
        rules.startStock = [:]
        let hungry = GameData(rules: rules, goods: data.goods, buildings: data.buildings)
        let sim = Simulation(data: hungry, terrain: Terrain(flatSize: 32))
        let before = sim.population
        sim.advance(days: rules.supplyCheckDays * 2)
        XCTAssertLessThan(sim.population, before)
    }

    func testCarriersMoveGoodsToStorage() throws {
        let sim = try flatSimulation()
        guard let start = sim.startCell else { return XCTFail("Kein Start") }
        let farm = try sim.place("getreidehof", at: GridPoint(x: start.x + 1, z: start.z + 1)).get()
        sim.advance(days: 30)
        // Niemand verarbeitet Getreide, also landet es im Lager.
        XCTAssertGreaterThan(sim.storedGoods["getreide", default: 0], 0)
        XCTAssertGreaterThan(farm.assignedWorkers, 0)
    }

    func testYearlyFinances() throws {
        // Genug Brot für das ganze Jahr, damit niemand wegzieht.
        let data = try GameData.loadDefault()
        var rules = data.rules
        rules.startStock = ["brot": 200]
        rules.taxPerResidentPerYear = 5
        let fed = GameData(rules: rules, goods: data.goods, buildings: data.buildings)
        let sim = Simulation(data: fed, terrain: Terrain(flatSize: 32))
        let start = sim.money
        let taxes = sim.population * sim.rules.taxPerResidentPerYear
        let upkeep = sim.buildings.reduce(0) { $0 + $1.definition.upkeepPerYear }
        sim.advance(days: sim.rules.daysPerYear)
        XCTAssertEqual(sim.year, 1)
        XCTAssertEqual(sim.money, start + taxes - upkeep)
        XCTAssertTrue(sim.events.contains { $0.hasPrefix("Jahr 1") })
    }

    func testSimulationIsDeterministic() throws {
        func run() throws -> (Int, Int, [String: Int]) {
            let data = try GameData.loadDefault()
            let sim = Simulation(data: data, seed: 7)
            if let s = sim.startCell {
                _ = sim.place("getreidehof", at: GridPoint(x: s.x + 1, z: s.z))
                _ = sim.place("muehle", at: GridPoint(x: s.x - 1, z: s.z))
            }
            sim.advance(days: 90)
            return (sim.money, sim.population, sim.storedGoods)
        }
        let a = try run()
        let b = try run()
        XCTAssertEqual(a.0, b.0)
        XCTAssertEqual(a.1, b.1)
        XCTAssertEqual(a.2, b.2)
    }
}
