import GameDomain
import GameSimulation

/// Income and expenses of the current and the previous year, plus the balance history,
/// prepared for the finance window.
struct FinanceSummary: Equatable {
    struct Row: Equatable, Identifiable {
        let category: FinanceCategory
        let currentYear: Int
        let previousYear: Int
        var id: FinanceCategory { category }
    }

    struct Point: Equatable, Identifiable {
        /// Fractional in-game year, e.g. 1.5 for the middle of the second year.
        let year: Double
        let balance: Int
        var id: Double { year }
    }

    /// Year number as shown to the player (the first year is year 1).
    var displayYear = 1
    var income: [Row] = []
    var expenses: [Row] = []
    var currentProfit = 0
    var previousProfit = 0
    var history: [Point] = []

    init() {}

    init(world: WorldState) {
        let ledger = world.ledger
        let year = world.clock.year
        let current = ledger.account(forYear: year)
        let previous = ledger.account(forYear: year - 1)

        func rows(_ categories: [FinanceCategory]) -> [Row] {
            categories.map { Row(category: $0, currentYear: current.total(for: $0), previousYear: previous.total(for: $0)) }
        }

        displayYear = year + 1
        income = rows(FinanceCategory.income)
        expenses = rows(FinanceCategory.expenses)
        currentProfit = current.profit
        previousProfit = previous.profit
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
        }
    }
}
