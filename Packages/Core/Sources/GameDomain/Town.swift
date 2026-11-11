/// Identifies a neighbouring town.
public struct TownID: Hashable, Comparable, Sendable, Codable {
    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: TownID, rhs: TownID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A natural resource placed on the map by the world generator, away from the start.
public enum Deposit: String, CaseIterable, Hashable, Sendable, Codable {
    /// Stone for quarries.
    case stone
    /// Sunny slopes for vineyards.
    case vines
}

/// What a kind of neighbouring town trades. Defined in the game data.
public struct TownTemplate: Hashable, Sendable, Codable {
    public var id: String
    /// English description, e.g. "Fishing village". The app localizes it.
    public var name: String
    public var population: Int
    /// Goods the town produces per trade period and offers at its stop.
    public var sells: [GoodAmount]
    /// Goods the town buys, with the amount it takes per trade period.
    public var buys: [GoodAmount]

    public init(id: String, name: String, population: Int, sells: [GoodAmount], buys: [GoodAmount]) {
        self.id = id
        self.name = name
        self.population = population
        self.sells = sells
        self.buys = buys
    }
}

/// A neutral town on the map. It trades with the player only through its stop, so
/// reaching it needs a road and a line.
public struct NeighbourTown: Identifiable, Hashable, Sendable, Codable {
    public let id: TownID
    /// Proper name of the town; not translated.
    public let name: String
    public let template: TownTemplate
    public let center: GridPoint
    /// The town's own stop, where it sells and buys.
    public let stopID: BuildingID
    /// Cells covered by the town's houses; nothing else can be built there.
    public let footprint: Set<GridPoint>
    /// Units of each good the town still buys in the current trade period.
    public var wanted: [GoodID: Int]

    public init(id: TownID, name: String, template: TownTemplate, center: GridPoint, stopID: BuildingID, footprint: Set<GridPoint>) {
        self.id = id
        self.name = name
        self.template = template
        self.center = center
        self.stopID = stopID
        self.footprint = footprint
        wanted = Dictionary(template.buys.map { ($0.good, $0.amount) }, uniquingKeysWith: +)
    }

    public func buys(_ good: GoodID) -> Bool {
        wanted[good, default: 0] > 0
    }
}
