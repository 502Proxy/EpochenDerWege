import Foundation

/// Warenbestand mit festem Platz pro Ware.
public struct Inventory: Equatable {
    public private(set) var items: [String: Int] = [:]
    public let capacityPerGood: Int

    public init(capacityPerGood: Int) {
        self.capacityPerGood = capacityPerGood
    }

    public func count(_ good: String) -> Int {
        items[good, default: 0]
    }

    public func space(_ good: String) -> Int {
        max(0, capacityPerGood - count(good))
    }

    public var total: Int {
        items.values.reduce(0, +)
    }

    /// Alle vorhandenen Waren, alphabetisch sortiert (deterministische Reihenfolge).
    public var sortedItems: [(good: String, count: Int)] {
        items.sorted { $0.key < $1.key }.map { (good: $0.key, count: $0.value) }
    }

    /// Legt bis zu `amount` Einheiten ein und gibt zurück, wie viele Platz hatten.
    @discardableResult
    public mutating func add(_ good: String, _ amount: Int) -> Int {
        let added = min(amount, space(good))
        if added > 0 {
            items[good, default: 0] += added
        }
        return added
    }

    /// Nimmt bis zu `amount` Einheiten heraus und gibt zurück, wie viele es waren.
    @discardableResult
    public mutating func remove(_ good: String, _ amount: Int) -> Int {
        let removed = min(amount, count(good))
        if removed > 0 {
            let rest = count(good) - removed
            items[good] = rest > 0 ? rest : nil
        }
        return removed
    }
}

public enum BuildingStatus: Equatable {
    case idle
    case working
    case missingInput
    case outputFull
    case noWorkers
    case noResources
    case storing
    case housing
}

public final class Building: Identifiable {
    public let id: Int
    public let definition: BuildingDefinition
    public let cell: GridPoint
    public let center: WorldPoint

    /// Eingangslager (Betriebe) bzw. Vorrat (Häuser).
    public internal(set) var input: Inventory
    /// Ausgangslager (Betriebe) bzw. Bestand (Lagerhaus).
    public internal(set) var output: Inventory

    public internal(set) var progress: Double = 0
    public internal(set) var cycleRunning = false
    public internal(set) var assignedWorkers = 0
    public internal(set) var resourceFactor: Double = 1
    public internal(set) var status: BuildingStatus = .idle
    public internal(set) var carriersOut = 0

    public internal(set) var residents = 0
    /// Anteil der erfüllten Bedürfnisse bei der letzten Prüfung (0...1).
    public internal(set) var lastSupply: Double = 1

    /// Waren, die bereits von Trägern hierher unterwegs sind.
    var incoming: [String: Int] = [:]
    /// Noch nicht gegessene Nahrung (Bruchteile) aus der letzten Prüfung.
    var foodOwed: Double = 0

    init(id: Int, definition: BuildingDefinition, cell: GridPoint, center: WorldPoint) {
        self.id = id
        self.definition = definition
        self.cell = cell
        self.center = center
        input = Inventory(capacityPerGood: definition.storagePerGood)
        output = Inventory(capacityPerGood: definition.storagePerGood)
    }

    public var workerFraction: Double {
        definition.workers == 0 ? 1 : Double(assignedWorkers) / Double(definition.workers)
    }

    /// Tatsächliche Arbeitsleistung aus Arbeitern und Rohstoffen in Reichweite.
    public var efficiency: Double {
        workerFraction * resourceFactor
    }
}

/// Ein Träger bringt Waren zu Fuß von A nach B und läuft danach leer zurück.
public struct Carrier: Identifiable {
    public enum Phase: Equatable {
        case delivering
        case returning
    }

    public let id: Int
    public let good: String
    public let amount: Int
    public let sourceID: Int
    public let targetID: Int
    public let from: WorldPoint
    public let to: WorldPoint
    public let distance: Double
    public internal(set) var phase: Phase = .delivering
    public internal(set) var traveled: Double = 0

    public var isLoaded: Bool { phase == .delivering }

    public var position: WorldPoint {
        let t = distance > 0 ? min(1, traveled / distance) : 1
        switch phase {
        case .delivering:
            return from.interpolated(to: to, t)
        case .returning:
            return to.interpolated(to: from, t)
        }
    }
}
