import GameDomain

/// Collects taxes and pays upkeep once per year.
public struct EconomySystem: SimulationSystem {
    public init() {}

    public func update(_ world: inout WorldState) {
        guard world.clock.isStartOfPeriod(days: world.rules.daysPerYear) else { return }
        var taxes = 0
        var upkeep = 0
        for building in world.buildings {
            upkeep += building.definition.upkeepPerYear
            if building.supplyRatio >= 0.5 {
                taxes += building.residents * world.rules.taxPerResidentPerYear
            }
        }
        world.treasury += taxes - upkeep
        world.emit(.yearClosed(year: world.clock.year, taxes: taxes, upkeep: upkeep))
    }
}
