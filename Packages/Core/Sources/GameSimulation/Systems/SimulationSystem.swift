import GameDomain

/// One aspect of the game rules, updated once per tick.
///
/// Systems are stateless: everything they need lives in the world state. Each
/// system decides from the clock whether it has work to do on the current tick.
/// The order of systems is fixed by `Simulation` and documented there.
public protocol SimulationSystem: Sendable {
    func update(_ world: inout WorldState)
}
