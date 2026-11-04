import GameDomain
@testable import GameSimulation
import Testing

@Suite("Ledger")
struct LedgerTests {
    @Test func accountsSumByCategory() {
        var ledger = Ledger()
        ledger.book(100, as: .taxes, year: 0)
        ledger.book(-40, as: .construction, year: 0)
        ledger.book(-10, as: .roads, year: 0)
        ledger.book(25, as: .refunds, year: 1)

        let first = ledger.account(forYear: 0)
        #expect(first.income == 100)
        #expect(first.expenses == -50)
        #expect(first.profit == 50)
        #expect(ledger.account(forYear: 1).total(for: .refunds) == 25)
        #expect(ledger.account(forYear: 7).profit == 0)
    }

    @Test func keepsOnlyRecentYears() {
        var ledger = Ledger()
        for year in 0..<(Ledger.keptYears + 3) {
            ledger.book(1, as: .taxes, year: year)
        }
        #expect(ledger.years.count == Ledger.keptYears)
        #expect(ledger.years.first?.year == 3)
    }

    @Test func everyTreasuryChangeIsBooked() throws {
        var simulation = try Fixtures.flatSimulation { $0.startingStock = [GoodAmount(good: "bread", amount: 200)] }
        let start = simulation.world.treasury
        try simulation.placeZoned("mill", x: 17, z: 16)
        simulation.execute(BuildRoadCommand(cells: RoadPlanner.path(from: GridPoint(x: 2, z: 2), to: GridPoint(x: 5, z: 2))))
        simulation.execute(DemolishRoadCommand(cells: [GridPoint(x: 2, z: 2)]))
        simulation.advance(days: simulation.world.rules.daysPerYear)

        let ledger = simulation.world.ledger
        let booked = ledger.years.reduce(0) { $0 + $1.profit }
        #expect(start + booked == simulation.world.treasury)

        let firstYear = ledger.account(forYear: 0)
        #expect(firstYear.total(for: .construction) == -600)
        #expect(firstYear.total(for: .roads) == -4 * simulation.world.rules.roadCostPerCell)
        #expect(firstYear.total(for: .refunds) == simulation.world.rules.roadCostPerCell / 2)
        #expect(firstYear.total(for: .taxes) == 20)
        #expect(firstYear.total(for: .upkeep) == -40)
    }

    @Test func monthsAndDetailsAreTracked() {
        var ledger = Ledger()
        ledger.book(16, as: .sales, year: 0, month: 2, detail: .good("bread"))
        ledger.book(8, as: .sales, year: 0, month: 2, detail: .good("bread"))
        ledger.book(4, as: .sales, year: 0, month: 3, detail: .good("fish"))

        #expect(ledger.account(forYear: 0, month: 2).total(for: .sales) == 24)
        #expect(ledger.account(forYear: 0, month: 3).total(for: .sales) == 4)
        #expect(ledger.account(forYear: 0).total(for: .sales, detail: .good("bread")) == 24)
        #expect(ledger.account(forYear: 0).total(for: .sales, detail: .good("fish")) == 4)
    }

    @Test func keepsOnlyRecentMonths() {
        var ledger = Ledger()
        for month in 0..<30 {
            ledger.book(1, as: .taxes, year: month / 12, month: month % 12)
        }
        #expect(ledger.months.count == Ledger.keptMonths)
    }

    @Test func constructionAndUpkeepAreBrokenDownByBuildingType() throws {
        var simulation = try Fixtures.flatSimulation { $0.startingStock = [GoodAmount(good: "bread", amount: 200)] }
        try simulation.placeZoned("mill", x: 17, z: 16)
        simulation.advance(days: simulation.world.rules.daysPerYear)
        let year = simulation.world.ledger.account(forYear: 0)
        #expect(year.total(for: .construction, detail: .building("mill")) == -600)
        #expect(year.total(for: .upkeep, detail: .building("mill")) == -20)
        #expect(year.total(for: .upkeep, detail: .building("storehouse")) == -20)
        #expect(simulation.world.ledger.account(forYear: 0, month: 11).total(for: .upkeep) == -40)
    }

    @Test func recordsDailyBalance() throws {
        var simulation = try Fixtures.flatSimulation()
        simulation.advance(days: 5)
        let history = simulation.world.ledger.history
        #expect(history.map(\.day) == [1, 2, 3, 4, 5])
        #expect(history.last?.balance == simulation.world.treasury)
    }
}
