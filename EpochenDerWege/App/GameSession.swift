import GameData
import GameDomain
import GameSimulation

/// One running game: simulation engine and presentation state.
///
/// Created by ``GameApp`` (the composition root) for a new or loaded world. Ending
/// the session stops its engine.
final class GameSession {
    let catalog: GameCatalog
    let engine: SimulationEngine
    let viewModel: GameViewModel

    init(catalog: GameCatalog, world: WorldState) {
        self.catalog = catalog
        engine = SimulationEngine(simulation: Simulation(world: world))
        viewModel = GameViewModel(engine: engine)
        engine.start()
    }

    deinit {
        engine.stop()
    }
}
