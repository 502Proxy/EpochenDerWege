/// Identifies a placed building. Unique for the lifetime of a world.
public struct BuildingID: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: BuildingID, rhs: BuildingID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String { "Building#\(rawValue)" }
}

/// Identifies a carrier walking between buildings.
public struct CarrierID: Hashable, Comparable, Sendable, Codable {
    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: CarrierID, rhs: CarrierID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Identifies a kind of good, for example `"bread"`. Defined in the game data.
public struct GoodID: Hashable, Comparable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
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

    public static func < (lhs: GoodID, rhs: GoodID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String { rawValue }
}

/// Identifies a kind of building, for example `"bakery"`. Defined in the game data.
public struct BuildingTypeID: Hashable, Comparable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
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

    public static func < (lhs: BuildingTypeID, rhs: BuildingTypeID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String { rawValue }
}
