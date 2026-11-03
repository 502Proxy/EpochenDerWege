/// How much of a good was produced and consumed in a period.
public struct GoodFlow: Hashable, Sendable, Codable {
    public var produced = 0
    public var consumed = 0

    public init(produced: Int = 0, consumed: Int = 0) {
        self.produced = produced
        self.consumed = consumed
    }
}

/// Production and consumption per good and year.
///
/// *Produced* counts outputs of production buildings. *Consumed* counts production
/// inputs, food eaten by residents and goods sold on by markets and workshops.
public struct GoodsStatistics: Hashable, Sendable, Codable {
    /// How many years are kept.
    public static let keptYears = 3

    private var years: [Int: [GoodID: GoodFlow]] = [:]

    public init() {}

    public func flow(of good: GoodID, year: Int) -> GoodFlow {
        years[year]?[good] ?? GoodFlow()
    }

    /// Goods with any recorded flow in the given years, sorted.
    public func goods(inYears yearsToInclude: [Int]) -> [GoodID] {
        Set(yearsToInclude.flatMap { years[$0]?.keys.map { $0 } ?? [] }).sorted()
    }

    public mutating func recordProduced(_ good: GoodID, amount: Int, year: Int) {
        guard amount > 0 else { return }
        years[year, default: [:]][good, default: GoodFlow()].produced += amount
        trim(currentYear: year)
    }

    public mutating func recordConsumed(_ good: GoodID, amount: Int, year: Int) {
        guard amount > 0 else { return }
        years[year, default: [:]][good, default: GoodFlow()].consumed += amount
        trim(currentYear: year)
    }

    private mutating func trim(currentYear: Int) {
        for year in years.keys where year <= currentYear - Self.keptYears {
            years[year] = nil
        }
    }
}
