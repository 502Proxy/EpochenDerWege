import GameData
import GameDomain
import Testing

@Suite("Game data")
struct GameDataTests {
    @Test func bundledCatalogLoadsAndValidates() throws {
        let catalog = try BundledCatalogRepository().loadCatalog()
        #expect(catalog.rules.ticksPerDay == 20)
        #expect(catalog.building("bakery")?.outputs == [GoodAmount(good: "bread", amount: 3)])
        #expect(catalog.good("bread")?.name == "Bread")
        #expect(catalog.firstBuilding(of: .storage)?.id == "storehouse")
    }

    @Test func missingResourceIsReported() {
        #expect(throws: GameDataError.resourceNotFound("doesNotExist.json")) {
            try BundledCatalogRepository(resourceName: "doesNotExist").loadCatalog()
        }
    }

    @Test func unknownGoodIsRejected() throws {
        let catalog = try BundledCatalogRepository().loadCatalog()
        var bakery = try #require(catalog.building("bakery"))
        bakery.inputs = [GoodAmount(good: "cheese", amount: 1)]
        let broken = GameCatalog(
            rules: catalog.rules,
            goods: catalog.goods,
            buildings: catalog.buildings.map { $0.id == "bakery" ? bakery : $0 }
        )
        #expect(throws: GameDataError.unknownGood("cheese", referencedBy: "bakery")) {
            try CatalogValidator.validate(broken)
        }
    }

    @Test func duplicateBuildingIsRejected() throws {
        let catalog = try BundledCatalogRepository().loadCatalog()
        let broken = GameCatalog(rules: catalog.rules, goods: catalog.goods, buildings: catalog.buildings + [catalog.buildings[0]])
        #expect(throws: GameDataError.duplicateBuilding(catalog.buildings[0].id)) {
            try CatalogValidator.validate(broken)
        }
    }
}
