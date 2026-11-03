import GameDomain

/// Cells between two corners, inclusive, row by row.
public enum ZonePlanner {
    public static func rectangle(from start: GridPoint, to end: GridPoint) -> [GridPoint] {
        var cells: [GridPoint] = []
        for z in min(start.z, end.z)...max(start.z, end.z) {
            for x in min(start.x, end.x)...max(start.x, end.x) {
                cells.append(GridPoint(x: x, z: z))
            }
        }
        return cells
    }

    /// Whether a cell can carry a zone: on the map and on land.
    public static func canZone(_ cell: GridPoint, in world: WorldState) -> Bool {
        world.terrain.contains(cell) && world.terrain.isLand(cell)
    }
}

/// Zones cells (free of charge). `kind == nil` removes zoning.
public struct ZoneCommand: GameCommand {
    public let cells: [GridPoint]
    public let kind: ZoneKind?

    public init(cells: [GridPoint], kind: ZoneKind?) {
        self.cells = cells
        self.kind = kind
    }

    public func execute(in world: inout WorldState) {
        var changed = 0
        for cell in Set(cells) {
            if let kind {
                guard ZonePlanner.canZone(cell, in: world), world.zones[cell] != kind else { continue }
                world.zones[cell] = kind
                changed += 1
            } else if world.zones.removeValue(forKey: cell) != nil {
                changed += 1
            }
        }
        if changed > 0 {
            world.emit(.zoneChanged(kind: kind, cells: changed))
        }
    }
}
