import GameDomain

/// The complete, authoritative state of a running game.
///
/// `WorldState` is a value type. The simulation mutates its own copy; every copy
/// handed out (a *snapshot*) is immutable from the reader's point of view and can be
/// sent across threads. Copies are cheap because the collections inside use
/// copy-on-write and the terrain is never mutated.
public struct WorldState: Sendable, Codable {
    public let catalog: GameCatalog
    public let terrain: Terrain

    public internal(set) var clock: GameClock
    /// Current money. Change it only through ``book(_:as:year:)`` so the ledger stays complete.
    public private(set) var treasury: Int
    /// Income and expenses by year and category, plus the balance history.
    public internal(set) var ledger = Ledger()
    /// Production and consumption per good and year.
    public internal(set) var goodsStatistics = GoodsStatistics()
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
    /// Neutral towns on the map, in founding order.
    public internal(set) var towns: [NeighbourTown] = []
    /// Highest settlement level reached, as an index into `catalog.settlementLevels`. Never goes down.
    public internal(set) var settlementLevel = 0
    /// Recent events, oldest first. Capped to `maximumEventCount`.
    public internal(set) var events: [EventRecord] = []

    private var indexByID: [BuildingID: Int] = [:]
    private var occupancy: [GridPoint: BuildingID] = [:]
    private var spatialIndex = SpatialIndex()
    private var nextBuildingID = 1
    private var nextCarrierID = 1
    private var nextEventSequence = 1
    private var nextLineID = 1
    private var nextVehicleID = 1
    private var nextTownID = 1

    /// How many events are kept for the UI.
    public static let maximumEventCount = 32

    public init(catalog: GameCatalog, terrain: Terrain) {
        self.catalog = catalog
        self.terrain = terrain
        clock = GameClock(ticksPerDay: catalog.rules.ticksPerDay, daysPerYear: catalog.rules.daysPerYear)
        treasury = catalog.rules.startingTreasury
    }

    public var rules: GameRules { catalog.rules }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case catalog, terrain, clock, treasury, ledger, goodsStatistics, buildings, carriers, unemployed
        case startCell, roads, tunnels, lines, vehicles, zones, towns, settlementLevel, events
        case nextBuildingID, nextCarrierID, nextEventSequence, nextLineID, nextVehicleID, nextTownID
    }

    /// Restores a saved world. Lookup tables are rebuilt from the buildings.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        catalog = try container.decode(GameCatalog.self, forKey: .catalog)
        terrain = try container.decode(Terrain.self, forKey: .terrain)
        clock = try container.decode(GameClock.self, forKey: .clock)
        treasury = try container.decode(Int.self, forKey: .treasury)
        ledger = try container.decode(Ledger.self, forKey: .ledger)
        goodsStatistics = try container.decode(GoodsStatistics.self, forKey: .goodsStatistics)
        buildings = try container.decode([Building].self, forKey: .buildings)
        carriers = try container.decode([Carrier].self, forKey: .carriers)
        unemployed = try container.decode(Int.self, forKey: .unemployed)
        startCell = try container.decodeIfPresent(GridPoint.self, forKey: .startCell)
        roads = try container.decode(Set<GridPoint>.self, forKey: .roads)
        tunnels = try container.decode(Set<GridPoint>.self, forKey: .tunnels)
        lines = try container.decode([TransportLine].self, forKey: .lines)
        vehicles = try container.decode([Vehicle].self, forKey: .vehicles)
        // Zones are stored as a sorted list of cell and kind, so the same world always gives the same file.
        zones = Dictionary(try container.decode([ZoneEntry].self, forKey: .zones).map { ($0.cell, $0.kind) }, uniquingKeysWith: { first, _ in first })
        towns = try container.decode([NeighbourTown].self, forKey: .towns)
        settlementLevel = try container.decode(Int.self, forKey: .settlementLevel)
        events = try container.decode([EventRecord].self, forKey: .events)
        nextBuildingID = try container.decode(Int.self, forKey: .nextBuildingID)
        nextCarrierID = try container.decode(Int.self, forKey: .nextCarrierID)
        nextEventSequence = try container.decode(Int.self, forKey: .nextEventSequence)
        nextLineID = try container.decode(Int.self, forKey: .nextLineID)
        nextVehicleID = try container.decode(Int.self, forKey: .nextVehicleID)
        nextTownID = try container.decode(Int.self, forKey: .nextTownID)
        for (index, building) in buildings.enumerated() {
            indexByID[building.id] = index
            occupancy[building.cell] = building.id
            spatialIndex.insert(building.id, at: building.center)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(catalog, forKey: .catalog)
        try container.encode(terrain, forKey: .terrain)
        try container.encode(clock, forKey: .clock)
        try container.encode(treasury, forKey: .treasury)
        try container.encode(ledger, forKey: .ledger)
        try container.encode(goodsStatistics, forKey: .goodsStatistics)
        try container.encode(buildings, forKey: .buildings)
        try container.encode(carriers, forKey: .carriers)
        try container.encode(unemployed, forKey: .unemployed)
        try container.encodeIfPresent(startCell, forKey: .startCell)
        // Sorted, so the same world always produces the same file.
        try container.encode(roads.sorted(by: Self.cellOrder), forKey: .roads)
        try container.encode(tunnels.sorted(by: Self.cellOrder), forKey: .tunnels)
        try container.encode(lines, forKey: .lines)
        try container.encode(vehicles, forKey: .vehicles)
        try container.encode(zones.keys.sorted(by: Self.cellOrder).map { ZoneEntry(cell: $0, kind: zones[$0] ?? .residential) }, forKey: .zones)
        try container.encode(towns, forKey: .towns)
        try container.encode(settlementLevel, forKey: .settlementLevel)
        try container.encode(events, forKey: .events)
        try container.encode(nextBuildingID, forKey: .nextBuildingID)
        try container.encode(nextCarrierID, forKey: .nextCarrierID)
        try container.encode(nextEventSequence, forKey: .nextEventSequence)
        try container.encode(nextLineID, forKey: .nextLineID)
        try container.encode(nextVehicleID, forKey: .nextVehicleID)
        try container.encode(nextTownID, forKey: .nextTownID)
    }

    private struct ZoneEntry: Codable {
        let cell: GridPoint
        let kind: ZoneKind
    }

    private static func cellOrder(_ a: GridPoint, _ b: GridPoint) -> Bool {
        (a.z, a.x) < (b.z, b.x)
    }

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

    /// Whether the cell belongs to a neighbouring town.
    public func isTownCell(_ cell: GridPoint) -> Bool {
        towns.contains { $0.footprint.contains(cell) }
    }

    public func town(_ id: TownID) -> NeighbourTown? {
        towns.first { $0.id == id }
    }

    /// The town a stop belongs to, if it is a town's stop.
    public func town(owningStop stopID: BuildingID) -> NeighbourTown? {
        building(stopID)?.townID.flatMap(town)
    }

    public func hasRoad(at cell: GridPoint) -> Bool {
        roads.contains(cell)
    }

    /// Buildings whose centre lies within `radius` metres of `point`, in placement order.
    public func buildings(within radius: Double, of point: WorldPoint) -> [Building] {
        spatialIndex.candidates(near: point, radius: radius).compactMap { id in
            guard let building = building(id), building.center.distance(to: point) <= radius else { return nil }
            return building
        }
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

    /// Everything of a good that exists: in buildings, on carriers and on vehicles.
    public func totalAmount(of good: GoodID) -> Int {
        buildings.reduce(0) { $0 + $1.input.count(of: good) + $1.output.count(of: good) }
            + carriers.reduce(0) { $0 + ($1.isLoaded && $1.cargo.good == good ? $1.cargo.amount : 0) }
            + vehicles.reduce(0) { $0 + $1.cargo[good, default: 0] }
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
        spatialIndex.insert(id, at: building.center)
        buildings.append(building)
        return id
    }

    @discardableResult
    mutating func removeBuilding(_ id: BuildingID) -> Building? {
        guard let index = indexByID[id] else { return nil }
        let removed = buildings.remove(at: index)
        occupancy[removed.cell] = nil
        indexByID[id] = nil
        spatialIndex.remove(id, at: removed.center)
        for i in index..<buildings.count {
            indexByID[buildings[i].id] = i
        }
        return removed
    }

    mutating func makeTownID() -> TownID {
        defer { nextTownID += 1 }
        return TownID(nextTownID)
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
    /// - Parameters:
    ///   - year: The year to book into; defaults to the current year.
    ///   - month: The month to book into; defaults to the current month.
    ///   - detail: What the booking was about, for breakdowns.
    mutating func book(_ amount: Int, as category: FinanceCategory, year: Int? = nil, month: Int? = nil, detail: LedgerDetail? = nil) {
        treasury += amount
        ledger.book(amount, as: category, year: year ?? clock.year, month: month ?? clock.month, detail: detail)
    }

    mutating func emit(_ event: SimulationEvent) {
        events.append(EventRecord(sequence: nextEventSequence, tick: clock.tick, event: event))
        nextEventSequence += 1
        if events.count > Self.maximumEventCount {
            events.removeFirst(events.count - Self.maximumEventCount)
        }
    }
}
