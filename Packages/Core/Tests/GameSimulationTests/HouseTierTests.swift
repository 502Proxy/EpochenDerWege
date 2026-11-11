import GameData
import GameDomain
@testable import GameSimulation
import Testing

@Suite("House tiers")
struct HouseTierTests {
    /// A world with the starting settlement and a full hut stocked with bread and `extra` goods.
    private func makeWorld(level: Int, extra: [GoodID] = []) throws -> (world: WorldState, index: Int) {
        var world = try Fixtures.flatSimulation().world
        world.settlementLevel = level
        let index = try #require(world.buildings.firstIndex { $0.definition.id == "house" })
        world.buildings[index].residents = world.buildings[index].definition.maxResidents
        world.buildings[index].input.add("bread", amount: 4)
        for good in extra {
            world.buildings[index].input.add(good, amount: 4)
        }
        return (world, index)
    }

    private func runChecks(_ count: Int, on house: inout Building, in world: WorldState) -> HouseTiers.Change? {
        var statistics = GoodsStatistics()
        var last: HouseTiers.Change?
        for _ in 0..<count {
            last = HouseTiers.check(&house, in: world, statistics: &statistics) ?? last
        }
        return last
    }

    @Test func catalogChainsHutHouseTownhouse() throws {
        let catalog = try Fixtures.catalog()
        let hut = try #require(catalog.building("house"))
        let house = try #require(catalog.nextTier(of: hut))
        let townhouse = try #require(catalog.nextTier(of: house))
        #expect(house.needs == ["clothing"])
        #expect(townhouse.needs?.contains("wine") == true)
        #expect(townhouse.maxResidents > house.maxResidents && house.maxResidents > hut.maxResidents)
        #expect(catalog.previousTier(of: house)?.id == hut.id)
        #expect(catalog.nextTier(of: townhouse) == nil)
    }

    @Test func hutUpgradesWhenClothingIsInStock() throws {
        let (world, index) = try makeWorld(level: 1, extra: ["clothing"])
        var house = world.buildings[index]
        let change = runChecks(world.rules.upgradeChecks, on: &house, in: world)
        #expect(change == .upgraded("citizenHouse"))
        #expect(house.definition.id == "citizenHouse")
        #expect(house.input.count(of: "clothing") > 0)
    }

    @Test func noUpgradeBeforeTheLevelIsReached() throws {
        let (world, index) = try makeWorld(level: 0, extra: ["clothing"])
        var house = world.buildings[index]
        #expect(runChecks(world.rules.upgradeChecks * 2, on: &house, in: world) == nil)
        #expect(house.definition.id == "house")
    }

    @Test func noUpgradeWithoutTheNextTiersGoods() throws {
        let (world, index) = try makeWorld(level: 2)
        var house = world.buildings[index]
        #expect(runChecks(world.rules.upgradeChecks * 2, on: &house, in: world) == nil)
    }

    @Test func houseDropsATierWhenClothingRunsOut() throws {
        var (world, index) = try makeWorld(level: 1)
        _ = index
        let citizenHouse = try #require(world.catalog.building("citizenHouse"))
        world.buildings[index].convert(to: citizenHouse)
        world.buildings[index].residents = citizenHouse.maxResidents
        var house = world.buildings[index]

        let change = runChecks(world.rules.downgradeChecks, on: &house, in: world)
        #expect(change == .downgraded("house"))
        #expect(house.definition.id == "house")
        #expect(house.residents <= house.definition.maxResidents)
    }

    @Test func housesOrderClothingOnlyOnceUnlocked() throws {
        let (locked, index) = try makeWorld(level: 0)
        #expect(NearestConsumerPlanner.demand(of: locked.buildings[index], for: "clothing", in: locked) == 0)
        let (unlocked, _) = try makeWorld(level: 1)
        #expect(NearestConsumerPlanner.demand(of: unlocked.buildings[index], for: "clothing", in: unlocked) > 0)
        #expect(NearestConsumerPlanner.demand(of: unlocked.buildings[index], for: "wine", in: unlocked) == 0)
    }

    @Test func higherTiersPayMoreTaxes() throws {
        let catalog = try Fixtures.catalog()
        let hut = try #require(catalog.building("house"))
        let townhouse = try #require(catalog.building("townhouse"))
        #expect((townhouse.taxPerResidentPerYear ?? 0) > (hut.taxPerResidentPerYear ?? catalog.rules.taxPerResidentPerYear))
    }

    @Test func validatorRejectsTierLoops() throws {
        let catalog = try Fixtures.catalog()
        let buildings = catalog.buildings.map { building -> BuildingDefinition in
            var copy = building
            if copy.id == "townhouse" {
                copy.upgradesTo = "house"
            }
            return copy
        }
        let looped = GameCatalog(rules: catalog.rules, goods: catalog.goods, buildings: buildings, vehicles: catalog.vehicles, settlementLevels: catalog.settlementLevels)
        #expect(throws: GameDataError.self) { try CatalogValidator.validate(looped) }
    }
}
