import GameDomain

/// The complete, authoritative state of a running game.
///
/// `WorldState` is a value type. The simulation mutates its own copy; every copy
/// handed out (a *snapshot*) is immutable from the reader's point of view and can be
/// sent across threads. Copies are cheap because the collections inside use
/// copy-on-write and the terrain is never mutated.
public struct WorldState: Sendable {
    public let catalog: GameCatalog
    public let terrain: Terrain

    public internal(set) var clock: GameClock
    /// Current money. Change it only through ``book(_:as:year:)`` so the ledger stays complete.
    public private(set) var treasury: Int
    /// Income and expenses by year and category, plus the balance history.
    public internal(set) var ledger = Ledger()
    /// Buildings in placement order. The order is stable, which keeps the simulation deterministic.
    public internal(set) var buildings: [Building] = []
    public internal(set) var carriers: [Carrier] = []
    /// Residents not employed in any building.
    public internal(set) var unemployed = 0
    /// Centre of the starting settlement, if one was founded.
    public internal(set) var startCell: GridPoint?
    /// Cells covered by roads, including tunnels.
    public internal(set) var roads: Set<GridPoint> = []
    /// Road cells that run through a tunnel. Always a subset of `roads`.
    public internal(set) var tunnels: Set<GridPoint> = []
    /// Transport lines in creation order.
    public internal(set) var lines: [TransportLine] = []
    /// Vehicles on all lines.
    public internal(set) var vehicles: [Vehicle] = []
    /// Zoned cells. A zone stays when a building is placed on it.
    public internal(set) var zones: [GridPoint: ZoneKind] = [:]
    /// Recent events, oldest first. Capped to `maximumEventCount`.
    public internal(set) var events: [EventRecord] = []

    private var indexByID: [BuildingID: Int] = [:]
    private var occupancy: [GridPoint: BuildingID] = [:]
    private var nextBuildingID = 1
    private var nextCarrierID = 1
    private var nextEventSequence = 1
    private var nextLineID = 1
    private var nextVehicleID = 1

    /// How many events are kept for the UI.
    public static let maximumEventCount = 32

    public init(catalog: GameCatalog, terrain: Terrain) {
        self.catalog = catalog
        self.terrain = terrain
        clock = GameClock(ticksPerDay: catalog.rules.ticksPerDay, daysPerYear: catalog.rules.daysPerYear)
        treasury = catalog.rules.startingTreasury
    }

    public var rules: GameRules { catalog.rules }

    // MARK: - Queries

    public func building(_ id: BuildingID) -> Building? {
        indexByID[id].map { buildings[$0] }
    }

    public func building(at cell: GridPoint) -> Building? {
        occupancy[cell].flatMap { building($0) }
    }

    /// Whether a building stands on the cell.
    public func isOccupied(_ cell: GridPoint) -> Bool {
        occupancy[cell] != nil
    }

    public func hasRoad(at cell: GridPoint) -> Bool {
        roads.contains(cell)
    }

    public var population: Int {
        buildings.reduce(0) { $0 + $1.residents }
    }

    public var workersNeeded: Int {
        buildings.reduce(0) { $0 + ($1.category == .production ? $1.definition.workers : 0) }
    }

    public var workersEmployed: Int {
        buildings.reduce(0) { $0 + $1.assignedWorkers }
    }

    /// Total stock of all storehouses, sorted by good.
    public var storedGoods: [GoodAmount] {
        var totals: [GoodID: Int] = [:]
        for building in buildings where building.category == .storage {
            for item in building.output.sortedItems {
                totals[item.good, default: 0] += item.amount
            }
        }
        return totals.keys.sorted().map { GoodAmount(good: $0, amount: totals[$0, default: 0]) }
    }

    public func storedAmount(of good: GoodID) -> Int {
        storedGoods.first { $0.good == good }?.amount ?? 0
    }

    /// Sequence number of the newest event, or 0 if there is none.
    public var latestEventSequence: Int {
        events.last?.sequence ?? 0
    }

    // MARK: - Mutation (simulation only)

    func index(of id: BuildingID) -> Int? {
        indexByID[id]
    }

    @discardableResult
    mutating func addBuilding(_ definition: BuildingDefinition, at cell: GridPoint, resourceFactor: Double) -> BuildingID {
        let id = BuildingID(nextBuildingID)
        nextBuildingID += 1
        var building = Building(id: id, definition: definition, cell: cell, center: terrain.center(of: cell))
        building.resourceFactor = resourceFactor
        indexByID[id] = buildings.count
        occupancy[cell] = id
        buildings.append(building)
        return id
    }

    @discardableResult
    mutating func removeBuilding(_ id: BuildingID) -> Building? {
        guard let index = indexByID[id] else { return nil }
        let removed = buildings.remove(at: index)
        occupancy[removed.cell] = nil
        indexByID[id] = nil
        for i in index..<buildings.count {
            indexByID[buildings[i].id] = i
        }
        return removed
    }

    mutating func makeLineID() -> LineID {
        defer { nextLineID += 1 }
        return LineID(nextLineID)
    }

    mutating func makeVehicleID() -> VehicleID {
        defer { nextVehicleID += 1 }
        return VehicleID(nextVehicleID)
    }

    public func line(_ id: LineID) -> TransportLine? {
        lines.first { $0.id == id }
    }

    /// Lines that call at a stop.
    public func lines(servingStop stop: BuildingID) -> [TransportLine] {
        lines.filter { $0.stops.contains(stop) }
    }

    mutating func makeCarrierID() -> CarrierID {
        defer { nextCarrierID += 1 }
        return CarrierID(nextCarrierID)
    }

    /// Changes the treasury and records the booking. Positive amounts are income.
    ///
    /// - Parameter year: The year to book into; defaults to the current year.
    mutating func book(_ amount: Int, as category: FinanceCategory, year: Int? = nil) {
        treasury += amount
        ledger.book(amount, as: category, year: year ?? clock.year)
    }

    mutating func emit(_ event: SimulationEvent) {
        events.append(EventRecord(sequence: nextEventSequence, tick: clock.tick, event: event))
        nextEventSequence += 1
        if events.count > Self.maximumEventCount {
            events.removeFirst(events.count - Self.maximumEventCount)
        }
    }
}
