import GameDomain
import GameSimulation

/// Windows that float above the map. Several can be open at once.
enum GamePanel: String, CaseIterable, Identifiable {
    case finances, goods, buildings, lines, saves

    var id: Self { self }

    /// Panels with a button and a key in the bottom bar's panel group.
    static let windows: [GamePanel] = [.finances, .goods, .buildings, .lines]

    var symbol: String {
        switch self {
        case .finances: "banknote"
        case .goods: "shippingbox"
        case .buildings: "building.2"
        case .lines: "point.topleft.down.to.point.bottomright.curvepath"
        case .saves: "externaldrive.fill"
        }
    }

    /// Key that opens and closes the panel.
    var shortcut: Character {
        switch self {
        case .finances: "f"
        case .goods: "g"
        case .buildings: "b"
        case .lines: "l"
        case .saves: "k"
        }
    }
}

/// A message in the notification stack, with a tone and an icon for quick reading.
struct GameNotification: Equatable, Identifiable {
    let id: Int
    let text: String
    let tone: StatusTone
    let symbol: String
    let expiresAt: ContinuousClock.Instant
}

/// What the mini map draws on top of the terrain image.
struct MiniMapContent: Equatable {
    struct Marker: Equatable {
        let cell: GridPoint
        let color: GameColor
    }

    /// Cells per map edge.
    var mapSize = 1
    var roads: [GridPoint] = []
    var buildings: [Marker] = []
    /// Neighbouring towns with their names.
    var towns: [(name: String, cell: GridPoint)] = []

    init() {}

    init(world: WorldState) {
        mapSize = world.terrain.size
        roads = world.roads.sorted { ($0.z, $0.x) < ($1.z, $1.x) }
        buildings = world.buildings.map { Marker(cell: $0.cell, color: $0.definition.color) }
        towns = world.towns.map { ($0.name, $0.center) }
    }

    static func == (lhs: MiniMapContent, rhs: MiniMapContent) -> Bool {
        lhs.mapSize == rhs.mapSize
            && lhs.roads == rhs.roads
            && lhs.buildings == rhs.buildings
            && lhs.towns.map(\.name) == rhs.towns.map(\.name)
            && lhs.towns.map(\.cell) == rhs.towns.map(\.cell)
    }
}

/// Where the camera looks, reported by the scene for the mini map.
struct CameraPose: Equatable {
    /// Point the camera looks at, in cells (fractional).
    var x: Double
    var z: Double
    /// Camera yaw in radians: the camera looks along (−sin, −cos) in x and z.
    var yaw: Double
}

/// The settlement's size class and the way to the next one.
struct SettlementProgress: Equatable {
    var level = 0
    var name = ""
    var population = 0
    /// Name of the next level; `nil` at the highest level.
    var nextName: String?
    /// Residents needed for the next level.
    var nextPopulation = 0
    /// Share of the way from the current level's threshold to the next, `0...1`.
    var progress = 0.0

    init() {}

    init(world: WorldState) {
        let catalog = world.catalog
        let levels = catalog.settlementLevels
        level = world.settlementLevel
        name = GameText.levelName(level, in: catalog)
        population = world.population
        guard levels.indices.contains(level + 1) else {
            progress = 1
            return
        }
        let start = levels[level].minimumPopulation
        let goal = levels[level + 1].minimumPopulation
        nextName = GameText.levelName(level + 1, in: catalog)
        nextPopulation = goal
        progress = min(1, max(0, Double(population - start) / Double(max(1, goal - start))))
    }
}
