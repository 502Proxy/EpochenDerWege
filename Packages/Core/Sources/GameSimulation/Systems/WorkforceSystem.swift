import GameDomain

/// Distributes residents to production buildings, oldest buildings first.
public struct WorkforceSystem: SimulationSystem {
    public init() {}

    public func update(_ world: inout WorldState) {
        if world.clock.isStartOfPeriod(days: 1) {
            Self.assignWorkers(in: &world)
        }
    }

    /// Reassigns all workers immediately. Called after buildings or residents change.
    public static func assignWorkers(in world: inout WorldState) {
        var available = world.population
        for index in world.buildings.indices where world.buildings[index].category == .production {
            let assigned = min(world.buildings[index].definition.workers, available)
            world.buildings[index].assignedWorkers = assigned
            available -= assigned
        }
        world.unemployed = available
    }
}
