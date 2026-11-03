/// An amount of one good, for example "2 grain".
public struct GoodAmount: Hashable, Sendable, Codable {
    public var good: GoodID
    public var amount: Int

    public init(good: GoodID, amount: Int) {
        self.good = good
        self.amount = amount
    }
}

/// An sRGB colour with components in `0...1`. Used by the prototype renderer.
public struct RGBColor: Hashable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// Global balancing rules. All values come from the game data so they can be tuned without code changes.
public struct GameRules: Hashable, Sendable, Codable {
    /// Simulation ticks per in-game day. At 10 ticks per second this is 2 seconds per day.
    public var ticksPerDay: Int
    public var daysPerYear: Int
    public var startingTreasury: Int
    /// Distance a carrier walks in one in-game day.
    public var carrierSpeedMetersPerDay: Double
    /// Units a carrier can carry at once.
    public var carrierCapacity: Int
    /// Maximum straight-line distance a carrier will walk to deliver goods.
    public var carrierRangeMeters: Double
    /// Carriers look for new jobs every this many ticks.
    public var dispatchIntervalTicks: Int
    /// Houses eat, grow or shrink every this many days.
    public var supplyCheckIntervalDays: Int
    /// Food each resident eats per supply check.
    public var foodPerResidentPerCheck: Double
    public var taxPerResidentPerYear: Int
    /// Buildings cannot be placed on steeper cells.
    public var maxSlopePercent: Double
    /// Share of the construction cost refunded on demolition.
    public var demolitionRefundPercent: Int
    /// Goods houses accept as food, in order of preference.
    public var foodGoods: [GoodID]
    public var startingHouses: Int
    public var startingResidentsPerHouse: Int
    /// Goods in the starting storehouse.
    public var startingStock: [GoodAmount]

    public init(
        ticksPerDay: Int,
        daysPerYear: Int,
        startingTreasury: Int,
        carrierSpeedMetersPerDay: Double,
        carrierCapacity: Int,
        carrierRangeMeters: Double,
        dispatchIntervalTicks: Int,
        supplyCheckIntervalDays: Int,
        foodPerResidentPerCheck: Double,
        taxPerResidentPerYear: Int,
        maxSlopePercent: Double,
        demolitionRefundPercent: Int,
        foodGoods: [GoodID],
        startingHouses: Int,
        startingResidentsPerHouse: Int,
        startingStock: [GoodAmount]
    ) {
        self.ticksPerDay = ticksPerDay
        self.daysPerYear = daysPerYear
        self.startingTreasury = startingTreasury
        self.carrierSpeedMetersPerDay = carrierSpeedMetersPerDay
        self.carrierCapacity = carrierCapacity
        self.carrierRangeMeters = carrierRangeMeters
        self.dispatchIntervalTicks = dispatchIntervalTicks
        self.supplyCheckIntervalDays = supplyCheckIntervalDays
        self.foodPerResidentPerCheck = foodPerResidentPerCheck
        self.taxPerResidentPerYear = taxPerResidentPerYear
        self.maxSlopePercent = maxSlopePercent
        self.demolitionRefundPercent = demolitionRefundPercent
        self.foodGoods = foodGoods
        self.startingHouses = startingHouses
        self.startingResidentsPerHouse = startingResidentsPerHouse
        self.startingStock = startingStock
    }
}

/// A kind of good.
public struct GoodDefinition: Identifiable, Hashable, Sendable, Codable {
    public var id: GoodID
    /// English display name. The app localizes it through its string catalog.
    public var name: String
    public var basePrice: Int
    public var color: RGBColor

    public init(id: GoodID, name: String, basePrice: Int, color: RGBColor) {
        self.id = id
        self.name = name
        self.basePrice = basePrice
        self.color = color
    }
}

public enum BuildingCategory: String, Hashable, Sendable, Codable {
    /// Turns inputs into outputs.
    case production
    /// Stores any good and hands it to consumers.
    case storage
    /// Home of residents; consumes food.
    case housing
}

/// Terrain a building needs nearby, such as forest for a woodcutter.
public struct ResourceRequirement: Hashable, Sendable, Codable {
    public var biome: Biome
    /// Search radius in cells.
    public var radius: Int
    /// With this many matching cells the building works at full efficiency.
    public var idealCount: Int

    public init(biome: Biome, radius: Int, idealCount: Int) {
        self.biome = biome
        self.radius = radius
        self.idealCount = idealCount
    }
}

/// A kind of building and its rules.
public struct BuildingDefinition: Identifiable, Hashable, Sendable, Codable {
    public var id: BuildingTypeID
    /// English display name. The app localizes it through its string catalog.
    public var name: String
    public var category: BuildingCategory
    public var cost: Int
    public var upkeepPerYear: Int
    public var workers: Int
    public var inputs: [GoodAmount]
    public var outputs: [GoodAmount]
    /// Length of one production cycle in days at full efficiency.
    public var cycleDays: Double
    /// Capacity per good, separately for input and output stock.
    public var storagePerGood: Int
    /// How many carriers may be on their way from this building at the same time.
    public var maxCarriers: Int
    /// Maximum number of residents (housing only).
    public var maxResidents: Int
    public var resource: ResourceRequirement?
    public var color: RGBColor

    public init(
        id: BuildingTypeID,
        name: String,
        category: BuildingCategory,
        cost: Int,
        upkeepPerYear: Int,
        workers: Int,
        inputs: [GoodAmount],
        outputs: [GoodAmount],
        cycleDays: Double,
        storagePerGood: Int,
        maxCarriers: Int,
        maxResidents: Int,
        resource: ResourceRequirement?,
        color: RGBColor
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.cost = cost
        self.upkeepPerYear = upkeepPerYear
        self.workers = workers
        self.inputs = inputs
        self.outputs = outputs
        self.cycleDays = cycleDays
        self.storagePerGood = storagePerGood
        self.maxCarriers = maxCarriers
        self.maxResidents = maxResidents
        self.resource = resource
        self.color = color
    }

    /// Whether this building consumes the given good as a production input.
    public func consumes(_ good: GoodID) -> Bool {
        inputs.contains { $0.good == good }
    }
}

/// All game data for one era: rules, goods and buildings.
public struct GameCatalog: Sendable, Codable {
    public let rules: GameRules
    public let goods: [GoodDefinition]
    public let buildings: [BuildingDefinition]

    private let goodsByID: [GoodID: GoodDefinition]
    private let buildingsByID: [BuildingTypeID: BuildingDefinition]

    public init(rules: GameRules, goods: [GoodDefinition], buildings: [BuildingDefinition]) {
        self.rules = rules
        self.goods = goods
        self.buildings = buildings
        goodsByID = Dictionary(goods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        buildingsByID = Dictionary(buildings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private enum CodingKeys: String, CodingKey {
        case rules, goods, buildings
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rules: try container.decode(GameRules.self, forKey: .rules),
            goods: try container.decode([GoodDefinition].self, forKey: .goods),
            buildings: try container.decode([BuildingDefinition].self, forKey: .buildings)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rules, forKey: .rules)
        try container.encode(goods, forKey: .goods)
        try container.encode(buildings, forKey: .buildings)
    }

    public func good(_ id: GoodID) -> GoodDefinition? {
        goodsByID[id]
    }

    public func building(_ id: BuildingTypeID) -> BuildingDefinition? {
        buildingsByID[id]
    }

    /// Returns a copy with different rules. Handy for tests and scenarios.
    public func replacingRules(_ rules: GameRules) -> GameCatalog {
        GameCatalog(rules: rules, goods: goods, buildings: buildings)
    }

    /// The first building of a category, e.g. the storehouse used for a new settlement.
    public func firstBuilding(of category: BuildingCategory) -> BuildingDefinition? {
        buildings.first { $0.category == category }
    }
}
