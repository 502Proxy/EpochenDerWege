/// What a booking is for. Income categories add money, expense categories remove it.
public enum FinanceCategory: String, CaseIterable, Hashable, Sendable, Codable {
    case taxes
    case sales
    case refunds
    case construction
    case roads
    case upkeep
    /// Buying vehicles and their yearly upkeep.
    case vehicles
    /// Goods bought from neighbouring towns.
    case purchases

    public var isIncome: Bool {
        switch self {
        case .taxes, .sales, .refunds: true
        case .construction, .roads, .upkeep, .vehicles, .purchases: false
        }
    }

    public static var income: [FinanceCategory] { allCases.filter(\.isIncome) }
    public static var expenses: [FinanceCategory] { allCases.filter { !$0.isIncome } }
}

/// What a booking was about, for breakdowns such as sales per good.
public enum LedgerDetail: Hashable, Sendable, Codable {
    case good(GoodID)
    case building(BuildingTypeID)
    case vehicle(VehicleTypeID)
}

/// Totals per category for one in-game year or month.
public struct PeriodAccount: Hashable, Sendable, Codable {
    /// Year since the start of the game, starting at 0.
    public let year: Int
    /// Month within the year (0–11), or `nil` for a whole year.
    public let month: Int?
    /// Signed totals: income is positive, expenses are negative.
    public private(set) var totals: [FinanceCategory: Int] = [:]
    /// Signed totals per category and detail, e.g. sales of bread.
    public private(set) var details: [FinanceCategory: [LedgerDetail: Int]] = [:]

    public init(year: Int, month: Int? = nil) {
        self.year = year
        self.month = month
    }

    public func total(for category: FinanceCategory, detail: LedgerDetail) -> Int {
        details[category]?[detail] ?? 0
    }

    public func total(for category: FinanceCategory) -> Int {
        totals[category, default: 0]
    }

    public var income: Int {
        FinanceCategory.income.reduce(0) { $0 + total(for: $1) }
    }

    /// Sum of expenses as a negative number.
    public var expenses: Int {
        FinanceCategory.expenses.reduce(0) { $0 + total(for: $1) }
    }

    public var profit: Int {
        income + expenses
    }

    mutating func add(_ amount: Int, to category: FinanceCategory, detail: LedgerDetail? = nil) {
        totals[category, default: 0] += amount
        if let detail {
            details[category, default: [:]][detail, default: 0] += amount
        }
    }
}

/// Treasury balance at the start of a day.
public struct BalanceSample: Hashable, Sendable, Codable {
    public let day: Int
    public let balance: Int

    public init(day: Int, balance: Int) {
        self.day = day
        self.balance = balance
    }
}

/// Bookkeeping of all money movements, grouped by year and category.
public struct Ledger: Hashable, Sendable, Codable {
    /// How many years of accounts are kept.
    public static let keptYears = 10
    /// How many daily balance samples are kept.
    public static let keptSamples = 600

    /// How many months of accounts are kept.
    public static let keptMonths = 24

    /// Yearly accounts, oldest first.
    public private(set) var years: [PeriodAccount] = []
    /// Monthly accounts, oldest first.
    public private(set) var months: [PeriodAccount] = []
    /// Daily balances, oldest first.
    public private(set) var history: [BalanceSample] = []

    public init() {}

    /// Account of a year; empty if nothing was booked in it.
    public func account(forYear year: Int) -> PeriodAccount {
        years.first { $0.year == year } ?? PeriodAccount(year: year)
    }

    /// Account of a month; empty if nothing was booked in it.
    public func account(forYear year: Int, month: Int) -> PeriodAccount {
        months.first { $0.year == year && $0.month == month } ?? PeriodAccount(year: year, month: month)
    }

    /// Books a signed amount: positive for income, negative for expenses.
    public mutating func book(_ amount: Int, as category: FinanceCategory, year: Int, month: Int = 0, detail: LedgerDetail? = nil) {
        guard amount != 0 else { return }
        Self.add(amount, category, detail, to: &years, year: year, month: nil, keep: Self.keptYears)
        Self.add(amount, category, detail, to: &months, year: year, month: month, keep: Self.keptMonths)
    }

    private static func add(
        _ amount: Int, _ category: FinanceCategory, _ detail: LedgerDetail?,
        to accounts: inout [PeriodAccount], year: Int, month: Int?, keep: Int
    ) {
        if let index = accounts.firstIndex(where: { $0.year == year && $0.month == month }) {
            accounts[index].add(amount, to: category, detail: detail)
            return
        }
        var account = PeriodAccount(year: year, month: month)
        account.add(amount, to: category, detail: detail)
        accounts.append(account)
        accounts.sort { ($0.year, $0.month ?? 0) < ($1.year, $1.month ?? 0) }
        if accounts.count > keep {
            accounts.removeFirst(accounts.count - keep)
        }
    }

    public mutating func recordBalance(_ balance: Int, day: Int) {
        history.append(BalanceSample(day: day, balance: balance))
        if history.count > Self.keptSamples {
            history.removeFirst(history.count - Self.keptSamples)
        }
    }
}
