import GameDomain
@testable import GameSimulation
import Testing

@Suite("Commercial and industrial zones")
struct CommerceTests {
    /// Settlement at (16, 16) with a road along z = 12 and zones north of it.
    private func townWithZones(_ kind: ZoneKind, rules: ((inout GameRules) -> Void)? = nil) throws -> Simulation {
        var simulation = try Fixtures.flatSimulation(rules: rules)
        simulation.execute(BuildRoadCommand(cells: RoadPlanner.path(from: GridPoint(x: 10, z: 12), to: GridPoint(x: 22, z: 12))))
        simulation.execute(ZoneCommand(cells: ZonePlanner.rectangle(from: GridPoint(x: 10, z: 11), to: GridPoint(x: 22, z: 11)), kind: kind))
        return simulation
    }

    private func buildings(_ type: BuildingTypeID, in simulation: Simulation) -> [Building] {
        simulation.world.buildings.filter { $0.definition.id == type }
    }

    @Test func townBuildsAMarketInACommercialZone() throws {
        var simulation = try townWithZones(.commercial)
        simulation.advance(days: simulation.world.rules.zoneGrowthIntervalDays)
        let market = try #require(buildings("market", in: simulation).first)
        #expect(simulation.world.zones[market.cell] == .commercial)
        #expect(market.cell.z == 11)
    }

    @Test func numberOfMarketsFollowsPopulation() throws {
        var simulation = try townWithZones(.commercial)
        simulation.advance(days: simulation.world.rules.zoneGrowthIntervalDays * 3)
        // 20 residents, one market per 15 residents.
        #expect(buildings("market", in: simulation).count == 1)
    }

    @Test func noMarketWithoutCommercialZone() throws {
        var simulation = try townWithZones(.industrial)
        simulation.advance(days: simulation.world.rules.zoneGrowthIntervalDays)
        #expect(buildings("market", in: simulation).isEmpty)
        #expect(buildings("workshop", in: simulation).count == 1)
    }

    @Test func marketsBuySurplusFoodAndPay() throws {
        var simulation = try townWithZones(.commercial) { $0.startingStock = [GoodAmount(good: "bread", amount: 200)] }
        simulation.advance(days: 30)

        let sales = simulation.world.ledger.account(forYear: 0).total(for: .sales)
        #expect(sales > 0)
        #expect(sales % 8 == 0, "Bread sells at its base price of 8")
        // Houses are still fed first.
        #expect(simulation.world.population == 20)
    }

    @Test func workshopsBuyRawMaterials() throws {
        var simulation = try townWithZones(.industrial)
        let woodBefore = simulation.world.storedAmount(of: "wood")
        simulation.advance(days: 30)
        #expect(simulation.world.storedAmount(of: "wood") < woodBefore)
        #expect(simulation.world.ledger.account(forYear: 0).total(for: .sales) > 0)
    }

    @Test func tradingConsumesStockSoDemandContinues() throws {
        var simulation = try townWithZones(.industrial)
        simulation.advance(days: 60)
        let workshop = try #require(buildings("workshop", in: simulation).first)
        // Starting stock is 30 wood; the workshop holds at most 10, so it must have sold on.
        #expect(simulation.world.storedAmount(of: "wood") < 20)
        #expect(workshop.input.count(of: "wood") <= workshop.input.capacityPerGood)
    }
}
