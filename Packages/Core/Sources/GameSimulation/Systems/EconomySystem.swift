import GameDomain

/// Records the daily balance and settles taxes and upkeep at the end of each year.
public struct EconomySystem: SimulationSystem {
    public init() {}

    public func update(_ world: inout WorldState) {
        if world.clock.isStartOfPeriod(days: 1) {
            world.ledger.recordBalance(world.treasury, day: world.clock.day)
        }
        guard world.clock.isStartOfPeriod(days: world.rules.daysPerYear) else { return }

        var taxes = 0
        var upkeep = 0
        for building in world.buildings {
            upkeep += building.definition.upkeepPerYear
            if building.supplyRatio >= 0.5 {
                taxes += building.residents * world.rules.taxPerResidentPerYear
            }
        }
        // The year that just ended is settled; the clock already shows the new year.
        let closedYear = world.clock.year - 1
        world.book(taxes, as: .taxes, year: closedYear)
        world.book(-upkeep, as: .upkeep, year: closedYear)
        let vehicleUpkeep = world.vehicles.reduce(0) { $0 + $1.definition.upkeepPerYear }
        world.book(-vehicleUpkeep, as: .vehicles, year: closedYear)
        world.emit(.yearClosed(year: world.clock.year, taxes: taxes, upkeep: upkeep))
    }
}
