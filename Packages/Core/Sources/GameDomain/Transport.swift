/// Identifies a kind of vehicle, for example `"oxCart"`. Defined in the game data.
public struct VehicleTypeID: Hashable, Comparable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: VehicleTypeID, rhs: VehicleTypeID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String { rawValue }
}

/// Identifies a transport line.
public struct LineID: Hashable, Comparable, Sendable, Codable {
    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: LineID, rhs: LineID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Identifies a vehicle.
public struct VehicleID: Hashable, Comparable, Sendable, Codable {
    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: VehicleID, rhs: VehicleID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A kind of vehicle and its rules.
public struct VehicleDefinition: Identifiable, Hashable, Sendable, Codable {
    public var id: VehicleTypeID
    /// English display name. The app localizes it through its string catalog.
    public var name: String
    /// Units of goods it carries in total.
    public var capacity: Int
    /// Distance it drives in one in-game day on a road.
    public var speedMetersPerDay: Double
    public var price: Int
    public var upkeepPerYear: Int
    public var color: GameColor

    public init(id: VehicleTypeID, name: String, capacity: Int, speedMetersPerDay: Double, price: Int, upkeepPerYear: Int, color: GameColor) {
        self.id = id
        self.name = name
        self.capacity = capacity
        self.speedMetersPerDay = speedMetersPerDay
        self.price = price
        self.upkeepPerYear = upkeepPerYear
        self.color = color
    }
}

/// A route the player defined: vehicles drive its stops in order and then start over.
public struct TransportLine: Identifiable, Hashable, Sendable, Codable {
    public let id: LineID
    /// Stops in driving order. A line needs at least two stops to run.
    public var stops: [BuildingID]

    public init(id: LineID, stops: [BuildingID]) {
        self.id = id
        self.stops = stops
    }

    /// Player-facing line number.
    public var number: Int { id.rawValue }
}

/// A vehicle driving a line.
public struct Vehicle: Identifiable, Hashable, Sendable, Codable {
    public enum Status: Hashable, Sendable, Codable {
        /// Waiting at a stop while loading and unloading.
        case loading
        case driving
        /// No road connection to the next stop.
        case noRoute
        /// The line has fewer than two stops.
        case idle
    }

    public let id: VehicleID
    public let definition: VehicleDefinition
    public let lineID: LineID
    /// Goods on board.
    public var cargo: [GoodID: Int] = [:]
    /// Index in the line's stops of the stop the vehicle is at or has just left.
    public var stopIndex = 0
    /// Waypoints of the current leg, from the last stop to the next; empty while at a stop.
    public var route: [WorldPoint] = []
    /// Metres driven on the current leg.
    public var driven: Double = 0
    /// Ticks left before leaving the current stop.
    public var dwellTicks = 0
    public var status: Status = .idle
    /// Where the vehicle is, kept current by the simulation.
    public var position: WorldPoint

    public init(id: VehicleID, definition: VehicleDefinition, lineID: LineID, position: WorldPoint) {
        self.id = id
        self.definition = definition
        self.lineID = lineID
        self.position = position
    }

    public var load: Int {
        cargo.values.reduce(0, +)
    }

    public var freeCapacity: Int {
        max(0, definition.capacity - load)
    }

    /// Direction of travel on the ground, or `nil` while standing.
    public var heading: WorldPoint? {
        guard route.count > 1, let next = Route.point(on: route, at: driven + 1) else { return nil }
        return WorldPoint(x: next.x - position.x, z: next.z - position.z)
    }
}

/// Helpers for polylines given as waypoints.
public enum Route {
    public static func length(of points: [WorldPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// The point `distance` metres along the polyline, clamped to its ends.
    public static func point(on points: [WorldPoint], at distance: Double) -> WorldPoint? {
        guard var previous = points.first else { return nil }
        var remaining = max(0, distance)
        for point in points.dropFirst() {
            let segment = previous.distance(to: point)
            if remaining <= segment {
                return segment > 0 ? previous.interpolated(to: point, fraction: remaining / segment) : point
            }
            remaining -= segment
            previous = point
        }
        return points.last
    }
}
