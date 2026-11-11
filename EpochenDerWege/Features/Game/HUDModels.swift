import GameDomain
import GameSimulation

/// Windows that float above the map. Several can be open at once.
enum GamePanel: String, CaseIterable, Identifiable {
    case finances, goods, buildings, lines

    var id: Self { self }

    var symbol: String {
        switch self {
        case .finances: "banknote"
        case .goods: "shippingbox"
        case .buildings: "building.2"
        case .lines: "point.topleft.down.to.point.bottomright.curvepath"
        }
    }

    /// Key that opens and closes the panel.
    var shortcut: Character {
        switch self {
        case .finances: "f"
        case .goods: "g"
        case .buildings: "b"
        case .lines: "l"
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

    init() {}

    init(world: WorldState) {
        mapSize = world.terrain.size
        roads = world.roads.sorted { ($0.z, $0.x) < ($1.z, $1.x) }
        buildings = world.buildings.map { Marker(cell: $0.cell, color: $0.definition.color) }
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
