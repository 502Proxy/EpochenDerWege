import Foundation
import GameSimulation

/// What a save list shows without loading the whole world.
public struct SaveGameSummary: Codable, Hashable, Sendable {
    public var name: String
    public var savedAt: Date
    /// Completed years at the time of saving.
    public var year: Int
    public var population: Int
    public var treasury: Int

    public init(name: String, savedAt: Date, world: WorldState) {
        self.name = name
        self.savedAt = savedAt
        year = world.clock.year
        population = world.population
        treasury = world.treasury
    }
}

/// A save on disk, as listed by a ``SaveGameRepository``.
public struct SaveGameEntry: Identifiable, Hashable, Sendable {
    /// File name; unique within the repository.
    public let id: String
    public let summary: SaveGameSummary
}

/// Why a save could not be read or written.
public enum SaveGameError: Error, Equatable, CustomStringConvertible {
    /// The file is not a save of this game.
    case notASaveGame
    /// The file was written by a newer version of the game.
    case newerFormat(Int)
    /// The save does not exist (any more).
    case notFound(String)
    case corrupted(String)

    public var description: String {
        switch self {
        case .notASaveGame: "The file is not a save game of Epochen der Wege."
        case .newerFormat(let version): "The save was written by a newer version of the game (format \(version))."
        case .notFound(let id): "The save '\(id)' does not exist."
        case .corrupted(let details): "The save is damaged: \(details)"
        }
    }
}

/// Stores and restores games (repository pattern). The app does not care whether
/// saves live in files, in iCloud or in memory.
public protocol SaveGameRepository: Sendable {
    /// All saves, newest first.
    func list() throws -> [SaveGameEntry]
    /// Saves the world under a name; an existing save with the same name is replaced.
    @discardableResult
    func save(_ world: WorldState, named name: String) throws -> SaveGameEntry
    func load(_ id: SaveGameEntry.ID) throws -> WorldState
    func delete(_ id: SaveGameEntry.ID) throws
}
