import Foundation
import GameData
import GameDomain
import GamePersistence
import GameSimulation
import Observation

/// The running app: the current game session and the save games.
///
/// Loading a save or starting a new game replaces the whole session (engine, view
/// model and scene), so no state of the old game can leak into the new one.
@Observable
final class GameApp {
    /// The game being played. Replaced on load and on new game.
    private(set) var session: GameSession
    /// Saves on disk, newest first.
    private(set) var saves: [SaveGameEntry] = []
    /// Result of the last save or load, for the saves panel.
    private(set) var message: Message?
    private(set) var isBusy = false

    struct Message: Equatable {
        let text: String
        let isError: Bool
    }

    @ObservationIgnored private let catalog: GameCatalog
    @ObservationIgnored private let repository: any SaveGameRepository

    /// Name of the quick save slot (⌘S).
    static let quickSaveName = "Quicksave"

    init(catalog: GameCatalog, repository: any SaveGameRepository, seed: UInt64) {
        self.catalog = catalog
        self.repository = repository
        session = GameSession(catalog: catalog, world: WorldFactory.makeWorld(catalog: catalog, seed: seed))
        refreshSaves()
    }

    /// The default app: antiquity data, saves in Application Support, reference map.
    static func makeDefault() throws -> GameApp {
        GameApp(
            catalog: try BundledCatalogRepository().loadCatalog(),
            repository: FileSaveGameRepository(directory: FileSaveGameRepository.defaultDirectory()),
            seed: 2026
        )
    }

    func clearMessage() {
        message = nil
    }

    func refreshSaves() {
        saves = (try? repository.list()) ?? []
    }

    /// Saves the current game. Encoding and writing happen off the main thread.
    func save(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let world = session.engine.snapshots.value.world
        await perform {
            try await Self.save(world, named: trimmed.isEmpty ? Self.quickSaveName : trimmed, in: self.repository)
        } success: { entry in
            String(localized: "Saved as “\(entry.summary.name)”.")
        }
    }

    func load(_ id: SaveGameEntry.ID) async {
        await perform {
            try await Self.load(id, from: self.repository)
        } success: { world in
            self.session = GameSession(catalog: world.catalog, world: world)
            return String(localized: "Game loaded.")
        }
    }

    func delete(_ id: SaveGameEntry.ID) {
        do {
            try repository.delete(id)
            message = nil
        } catch {
            message = Message(text: String(describing: error), isError: true)
        }
        refreshSaves()
    }

    /// Starts a new game on a new map.
    func newGame() {
        let seed = UInt64.random(in: 1...UInt64(UInt32.max))
        session = GameSession(catalog: catalog, world: WorldFactory.makeWorld(catalog: catalog, seed: seed))
        message = nil
    }

    // MARK: - Background work

    private func perform<Value: Sendable>(
        _ work: () async throws -> Value,
        success: (Value) -> String
    ) async {
        guard !isBusy else { return }
        isBusy = true
        defer {
            isBusy = false
            refreshSaves()
        }
        do {
            let value = try await work()
            message = Message(text: success(value), isError: false)
        } catch {
            message = Message(text: String(describing: error), isError: true)
        }
    }

    @concurrent
    private nonisolated static func save(_ world: WorldState, named name: String, in repository: any SaveGameRepository) async throws -> SaveGameEntry {
        try repository.save(world, named: name)
    }

    @concurrent
    private nonisolated static func load(_ id: SaveGameEntry.ID, from repository: any SaveGameRepository) async throws -> WorldState {
        try repository.load(id)
    }
}
