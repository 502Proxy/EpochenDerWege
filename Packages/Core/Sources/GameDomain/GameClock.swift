/// In-game time, counted in simulation ticks.
public struct GameClock: Hashable, Sendable, Codable {
    public private(set) var tick = 0
    public let ticksPerDay: Int
    public let daysPerYear: Int

    public init(ticksPerDay: Int, daysPerYear: Int) {
        precondition(ticksPerDay > 0 && daysPerYear > 0, "Clock needs positive day and year lengths")
        self.ticksPerDay = ticksPerDay
        self.daysPerYear = daysPerYear
    }

    public mutating func advance() {
        tick += 1
    }

    /// Days since the start of the game.
    public var day: Int { tick / ticksPerDay }
    /// Completed years since the start of the game.
    public var year: Int { day / daysPerYear }
    /// Day within the current year, starting at 0.
    public var dayOfYear: Int { day % daysPerYear }

    /// Months per in-game year, used for finance figures.
    public static let monthsPerYear = 12

    /// Month within the current year, starting at 0.
    public var month: Int { dayOfYear * Self.monthsPerYear / daysPerYear }

    /// `true` on the first tick of every `days`-day period.
    public func isStartOfPeriod(days: Int) -> Bool {
        isMultiple(ofTicks: ticksPerDay * max(1, days))
    }

    /// `true` when the current tick is a multiple of `ticks`.
    public func isMultiple(ofTicks ticks: Int) -> Bool {
        tick > 0 && tick % max(1, ticks) == 0
    }
}
