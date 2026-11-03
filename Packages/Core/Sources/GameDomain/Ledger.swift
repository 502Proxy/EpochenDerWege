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

    public var isIncome: Bool {
        switch self {
        case .taxes, .sales, .refunds: true
        case .construction, .roads, .upkeep, .vehicles: false
        }
    }

    public static var income: [FinanceCategory] { allCases.filter(\.isIncome) }
    public static var expenses: [FinanceCategory] { allCases.filter { !$0.isIncome } }
}

/// Totals per category for one in-game year.
public struct YearAccount: Hashable, Sendable, Codable {
    /// Year since the start of the game, starting at 0.
    public let year: Int
    /// Signed totals: income is positive, expenses are negative.
    public private(set) var totals: [FinanceCategory: Int] = [:]

    public init(year: Int) {
        self.year = year
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

    mutating func add(_ amount: Int, to category: FinanceCategory) {
        totals[category, default: 0] += amount
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

    /// Accounts, oldest first.
    public private(set) var years: [YearAccount] = []
    /// Daily balances, oldest first.
    public private(set) var history: [BalanceSample] = []

    public init() {}

    /// Account of a year; empty if nothing was booked in it.
    public func account(forYear year: Int) -> YearAccount {
        years.first { $0.year == year } ?? YearAccount(year: year)
    }

    /// Books a signed amount: positive for income, negative for expenses.
    public mutating func book(_ amount: Int, as category: FinanceCategory, year: Int) {
        guard amount != 0 else { return }
        if let index = years.firstIndex(where: { $0.year == year }) {
            years[index].add(amount, to: category)
        } else {
            var account = YearAccount(year: year)
            account.add(amount, to: category)
            years.append(account)
            years.sort { $0.year < $1.year }
            if years.count > Self.keptYears {
                years.removeFirst(years.count - Self.keptYears)
            }
        }
    }

    public mutating func recordBalance(_ balance: Int, day: Int) {
        history.append(BalanceSample(day: day, balance: balance))
        if history.count > Self.keptSamples {
            history.removeFirst(history.count - Self.keptSamples)
        }
    }
}
