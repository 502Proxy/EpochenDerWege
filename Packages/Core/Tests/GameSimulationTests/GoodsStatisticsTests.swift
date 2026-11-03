import GameDomain
@testable import GameSimulation
import Testing

@Suite("Goods statistics")
struct GoodsStatisticsTests {
    @Test func countsProducedAndConsumedPerYear() {
        var statistics = GoodsStatistics()
        statistics.recordProduced("grain", amount: 4, year: 0)
        statistics.recordConsumed("grain", amount: 2, year: 0)
        statistics.recordProduced("grain", amount: 1, year: 1)
        #expect(statistics.flow(of: "grain", year: 0) == GoodFlow(produced: 4, consumed: 2))
        #expect(statistics.flow(of: "grain", year: 1) == GoodFlow(produced: 1, consumed: 0))
        #expect(statistics.goods(inYears: [0, 1]) == ["grain"])
    }

    @Test func dropsOldYears() {
        var statistics = GoodsStatistics()
        statistics.recordProduced("wood", amount: 1, year: 0)
        statistics.recordProduced("wood", amount: 1, year: GoodsStatistics.keptYears)
        #expect(statistics.flow(of: "wood", year: 0).produced == 0)
    }

    @Test func breadChainIsRecorded() throws {
        var simulation = try Fixtures.flatSimulation()
        try simulation.place("grainFarm", x: 15, z: 16)
        try simulation.placeZoned("mill", x: 17, z: 16)
        try simulation.placeZoned("bakery", x: 16, z: 17)
        simulation.advance(days: 30)

        let statistics = simulation.world.goodsStatistics
        #expect(statistics.flow(of: "grain", year: 0).produced > 0)
        #expect(statistics.flow(of: "grain", year: 0).consumed > 0)
        #expect(statistics.flow(of: "bread", year: 0).consumed > 0, "Residents eat bread")
        #expect(simulation.world.totalAmount(of: "wood") == 30, "Starting wood is untouched")
    }
}
