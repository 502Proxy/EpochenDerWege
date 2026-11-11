/// What a building is currently doing. Drives the status marker and the inspector.
public enum BuildingStatus: Hashable, Sendable, Codable {
    case idle
    case working
    case missingInput
    case outputFull
    case noWorkers
    case noResources
    case storing
    case housing
    /// A commerce building has goods and is selling them to the townspeople.
    case trading
    /// A commerce building waits for deliveries.
    case awaitingGoods
    /// Switched off by the player.
    case paused
}

/// How eagerly carriers deliver to a building.
public enum DeliveryPriority: Int, CaseIterable, Comparable, Hashable, Sendable, Codable {
    case low = -1
    case normal = 0
    case high = 1

    public static func < (lhs: DeliveryPriority, rhs: DeliveryPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A placed building.
///
/// `Building` is a value type: a copy taken for rendering can never change the
/// simulation. The simulation owns the authoritative copy inside its world state.
public struct Building: Identifiable, Hashable, Sendable, Codable {
    public let id: BuildingID
    /// The building type. Changes only when a house moves to another tier.
    public private(set) var definition: BuildingDefinition
    public let cell: GridPoint
    public let center: WorldPoint

    /// Production input stock, or the food stock of a house.
    public var input: Inventory
    /// Production output stock, or the stock of a storehouse.
    public var output: Inventory

    /// Progress of the running production cycle in `0...1`.
    public var progress: Double = 0
    public var isCycleRunning = false
    public var assignedWorkers = 0
    /// Share of the ideal resource terrain in reach, `0...1`.
    public var resourceFactor: Double = 1
    public var status: BuildingStatus = .idle
    /// Carriers currently on their way from this building (including the walk back).
    public var activeCarriers = 0

    public var residents = 0
    /// Share of needs met at the last supply check, `0...1`.
    public var supplyRatio: Double = 1
    /// Goods already on their way to this building.
    public var incoming: [GoodID: Int] = [:]
    /// Food owed from the last supply check (fractions of a unit).
    public var unpaidFood: Double = 0
    /// Switched off by the player: no work, no workers, no deliveries.
    public var isPaused = false
    /// How eagerly carriers deliver here.
    public var priority: DeliveryPriority = .normal
    /// Supply checks in a row a house has met all needs of its next tier.
    public var upgradeProgress = 0
    /// Supply checks in a row a house has missed one of its own needs.
    public var missingNeedChecks = 0

    /// Whether the player may pause the building and set its priority.
    public var isConfigurable: Bool {
        category == .production || category == .commerce || category == .storage
    }

    public init(id: BuildingID, definition: BuildingDefinition, cell: GridPoint, center: WorldPoint) {
        self.id = id
        self.definition = definition
        self.cell = cell
        self.center = center
        input = Inventory(capacityPerGood: definition.storagePerGood)
        output = Inventory(capacityPerGood: definition.storagePerGood)
    }

    public var category: BuildingCategory { definition.category }

    /// Turns the building into another type of the same footprint, e.g. a house into
    /// the next tier. Stock is kept as far as the new storage allows.
    public mutating func convert(to newDefinition: BuildingDefinition) {
        var newInput = Inventory(capacityPerGood: newDefinition.storagePerGood)
        for item in input.sortedItems {
            newInput.add(item.good, amount: item.amount)
        }
        var newOutput = Inventory(capacityPerGood: newDefinition.storagePerGood)
        for item in output.sortedItems {
            newOutput.add(item.good, amount: item.amount)
        }
        definition = newDefinition
        input = newInput
        output = newOutput
        residents = min(residents, newDefinition.maxResidents)
        upgradeProgress = 0
        missingNeedChecks = 0
    }

    public var workerRatio: Double {
        definition.workers == 0 ? 1 : Double(assignedWorkers) / Double(definition.workers)
    }

    /// Effective work rate from staffing and resources in reach.
    public var efficiency: Double {
        workerRatio * resourceFactor
    }

    public func incomingAmount(of good: GoodID) -> Int {
        incoming[good, default: 0]
    }
}
