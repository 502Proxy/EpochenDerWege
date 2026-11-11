import GameDomain
import GameSimulation

/// One transport line, prepared for the lines window.
struct LineSummary: Equatable, Identifiable {
    let id: LineID
    let number: Int
    let stopNames: [String]
    let vehicles: Int
    let cargo: Int
    let capacity: Int
    /// Whether any vehicle of the line cannot reach its next stop.
    let hasRouteProblem: Bool
    let color: GameColor

    static func make(for world: WorldState) -> [LineSummary] {
        world.lines.map { line in
            let vehicles = world.vehicles.filter { $0.lineID == line.id }
            return LineSummary(
                id: line.id,
                number: line.number,
                stopNames: line.stops.map { GameText.stopName($0, in: world) },
                vehicles: vehicles.count,
                cargo: vehicles.reduce(0) { $0 + $1.load },
                capacity: vehicles.reduce(0) { $0 + $1.definition.capacity },
                hasRouteProblem: vehicles.contains { $0.status == .noRoute } || line.stops.count < 2,
                color: color(for: line.id)
            )
        }
    }

    /// A distinct colour per line, used for its badge.
    static func color(for id: LineID) -> GameColor {
        let palette = [
            GameColor(red: 0.90, green: 0.30, blue: 0.25),
            GameColor(red: 0.25, green: 0.55, blue: 0.90),
            GameColor(red: 0.30, green: 0.70, blue: 0.35),
            GameColor(red: 0.85, green: 0.60, blue: 0.15),
            GameColor(red: 0.60, green: 0.35, blue: 0.80),
            GameColor(red: 0.20, green: 0.70, blue: 0.70),
        ]
        return palette[(id.rawValue - 1) % palette.count]
    }
}
