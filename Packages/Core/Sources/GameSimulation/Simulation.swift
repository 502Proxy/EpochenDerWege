import GameDomain

/// Advances a world by fixed time steps and applies player commands.
///
/// Each tick runs the systems in this order:
///
/// 1. ``WorkforceSystem`` – once per day, assign residents to jobs
/// 2. ``ProductionSystem`` – run production cycles
/// 3. ``LogisticsSystem`` – dispatch and move carriers
/// 4. ``PopulationSystem`` – feed houses, grow or shrink them
/// 5. ``EconomySystem`` – once per year, taxes and upkeep
/// 6. ``TownGrowthSystem`` – every few days, towns build houses in residential zones
///
/// `Simulation` is deterministic: the same world, commands and tick count always
/// produce the same result. It does no timing of its own; see ``SimulationEngine``.
public struct Simulation: Sendable {
    public private(set) var world: WorldState
    private let systems: [any SimulationSystem]

    public init(world: WorldState, systems: [any SimulationSystem] = Simulation.defaultSystems()) {
        self.world = world
        self.systems = systems
    }

    public static func defaultSystems() -> [any SimulationSystem] {
        [
            WorkforceSystem(),
            ProductionSystem(),
            LogisticsSystem(),
            PopulationSystem(),
            EconomySystem(),
            TownGrowthSystem(),
        ]
    }

    /// Advances the world by one tick.
    public mutating func step() {
        world.clock.advance()
        for system in systems {
            system.update(&world)
        }
    }

    public mutating func step(ticks: Int) {
        for _ in 0..<max(0, ticks) {
            step()
        }
    }

    public mutating func advance(days: Int) {
        step(ticks: days * world.rules.ticksPerDay)
    }

    public mutating func execute(_ command: any GameCommand) {
        command.execute(in: &world)
    }
}
