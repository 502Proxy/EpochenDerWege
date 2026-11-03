import GameData
import GameDomain
import GameSimulation

/// Composition root of a running game.
///
/// Wires the data layer, the simulation engine and the presentation layer together.
/// This is the only place that knows about concrete implementations; everything
/// else receives its dependencies through initialisers.
final class GameSession {
    let catalog: GameCatalog
    let engine: SimulationEngine
    let viewModel: GameViewModel

    init(catalog: GameCatalog, seed: UInt64) {
        self.catalog = catalog
        let world = WorldFactory.makeWorld(catalog: catalog, seed: seed)
        engine = SimulationEngine(simulation: Simulation(world: world))
        viewModel = GameViewModel(engine: engine)
        engine.start()
    }

    deinit {
        engine.stop()
    }

    /// The default game: antiquity data set on the reference map.
    static func makeDefault(repository: any GameCatalogRepository = BundledCatalogRepository()) throws -> GameSession {
        GameSession(catalog: try repository.loadCatalog(), seed: 2026)
    }
}
