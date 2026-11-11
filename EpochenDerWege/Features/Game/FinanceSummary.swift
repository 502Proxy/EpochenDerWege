import GameDomain
import GameSimulation

/// Finance figures prepared for the finance window: income and expenses for the
/// current and previous month and year, breakdowns and the balance history.
struct FinanceSummary: Equatable {
    /// Signed amounts for one row across the four periods shown.
    struct Amounts: Equatable {
        var thisMonth = 0
        var lastMonth = 0
        var thisYear = 0
        var lastYear = 0
    }

    struct Row: Equatable, Identifiable {
        let id: String
        let title: String
        let amounts: Amounts
    }

    struct Point: Equatable, Identifiable {
        /// Fractional in-game year, e.g. 1.5 for the middle of the second year.
        let year: Double
        let balance: Int
        var id: Double { year }
    }

    /// Year number as shown to the player (the first year is year 1).
    var displayYear = 1
    /// Month number as shown to the player (1–12).
    var displayMonth = 1
    var income: [Row] = []
    var expenses: [Row] = []
    var profit = Amounts()
    /// Sales per good, largest first.
    var salesByGood: [Row] = []
    /// Construction, upkeep and vehicle costs per building or vehicle type, largest first.
    var costsByType: [Row] = []
    var history: [Point] = []

    init() {}

    init(world: WorldState) {
        let ledger = world.ledger
        let catalog = world.catalog
        let year = world.clock.year
        let month = world.clock.month
        let previousMonth = month == 0 ? (year - 1, GameClock.monthsPerYear - 1) : (year, month - 1)
        let accounts = (
            thisMonth: ledger.account(forYear: year, month: month),
            lastMonth: ledger.account(forYear: previousMonth.0, month: previousMonth.1),
            thisYear: ledger.account(forYear: year),
            lastYear: ledger.account(forYear: year - 1)
        )

        func amounts(_ value: (PeriodAccount) -> Int) -> Amounts {
            Amounts(
                thisMonth: value(accounts.thisMonth),
                lastMonth: value(accounts.lastMonth),
                thisYear: value(accounts.thisYear),
                lastYear: value(accounts.lastYear)
            )
        }

        displayYear = year + 1
        displayMonth = month + 1
        income = FinanceCategory.income.map { category in
            Row(id: category.rawValue, title: GameText.name(of: category), amounts: amounts { $0.total(for: category) })
        }
        expenses = FinanceCategory.expenses.map { category in
            Row(id: category.rawValue, title: GameText.name(of: category), amounts: amounts { $0.total(for: category) })
        }
        profit = amounts(\.profit)

        // Breakdowns cover this and last year.
        let years = [accounts.thisYear, accounts.lastYear]
        let goods = Set(years.flatMap { $0.details[.sales]?.keys.map { $0 } ?? [] })
        salesByGood = goods.compactMap { detail -> Row? in
            guard case .good(let good) = detail else { return nil }
            return Row(
                id: good.rawValue,
                title: GameText.goodName(good, in: catalog),
                amounts: amounts { $0.total(for: .sales, detail: detail) }
            )
        }
        .sorted { $0.amounts.thisYear + $0.amounts.lastYear > $1.amounts.thisYear + $1.amounts.lastYear }

        let costCategories: [FinanceCategory] = [.construction, .upkeep, .vehicles]
        let types = Set(years.flatMap { account in costCategories.flatMap { account.details[$0]?.keys.map { $0 } ?? [] } })
        costsByType = types.compactMap { detail -> Row? in
            let title: String
            switch detail {
            case .building(let type): title = GameText.buildingName(type, in: catalog)
            case .vehicle(let type): title = catalog.vehicle(type).map(GameText.name(of:)) ?? type.rawValue
            case .good: return nil
            }
            return Row(
                id: String(describing: detail),
                title: title,
                amounts: amounts { account in costCategories.reduce(0) { $0 + account.total(for: $1, detail: detail) } }
            )
        }
        .sorted { $0.amounts.thisYear + $0.amounts.lastYear < $1.amounts.thisYear + $1.amounts.lastYear }

        let daysPerYear = Double(world.rules.daysPerYear)
        history = ledger.history.map { Point(year: Double($0.day) / daysPerYear + 1, balance: $0.balance) }
    }
}

extension GameText {
    static func name(of category: FinanceCategory) -> String {
        switch category {
        case .taxes: String(localized: "Taxes")
        case .sales: String(localized: "Sales")
        case .refunds: String(localized: "Refunds")
        case .construction: String(localized: "Construction")
        case .roads: String(localized: "Roads")
        case .upkeep: String(localized: "Upkeep")
        case .vehicles: String(localized: "Vehicles")
        case .purchases: String(localized: "Purchases from towns")
        }
    }
}
