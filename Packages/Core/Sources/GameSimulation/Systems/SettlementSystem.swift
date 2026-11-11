import GameDomain

/// Raises the settlement level when the population reaches the next threshold.
///
/// Levels are never lost: the highest level reached stays, so buildings unlocked by
/// it remain available even if residents leave for a while.
public struct SettlementSystem: SimulationSystem {
    public init() {}

    public func update(_ world: inout WorldState) {
        guard world.clock.isStartOfPeriod(days: 1) else { return }
        Self.updateLevel(in: &world)
    }

    static func updateLevel(in world: inout WorldState) {
        let reachable = world.catalog.settlementLevel(forPopulation: world.population)
        while world.settlementLevel < reachable {
            world.settlementLevel += 1
            world.emit(.settlementLevelReached(world.settlementLevel))
        }
    }
}
