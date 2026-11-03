import Foundation

public enum PlacementError: Error, Equatable {
    case unknownBuilding
    case outOfBounds
    case water
    case tooSteep(Double)
    case occupied
    case notEnoughMoney(Int)
    case missingResource(Biome)

    public var message: String {
        switch self {
        case .unknownBuilding:
            return "Unbekanntes Gebäude."
        case .outOfBounds:
            return "Außerhalb der Karte."
        case .water:
            return "Hier ist Wasser."
        case .tooSteep(let percent):
            return "Zu steil (\(Int(percent)) % Steigung)."
        case .occupied:
            return "Hier steht schon etwas."
        case .notEnoughMoney(let cost):
            return "Nicht genug Geld (\(cost) Taler nötig)."
        case .missingResource(let biome):
            return "Kein \(biome.germanName) in der Nähe."
        }
    }
}

extension Biome {
    public var germanName: String {
        switch self {
        case .water: return "Wasser"
        case .sand: return "Sand"
        case .grass: return "Grasland"
        case .forest: return "Wald"
        case .rock: return "Fels"
        case .snow: return "Schnee"
        }
    }
}

/// Der komplette Spielzustand. Kennt keine Grafik – die Darstellung liest nur und schickt Befehle.
public final class Simulation {
    public let data: GameData
    public let terrain: Terrain
    public var rules: Rules { data.rules }

    public private(set) var buildings: [Building] = []
    public private(set) var carriers: [Carrier] = []
    public private(set) var money: Int
    public private(set) var tick = 0
    public private(set) var freeWorkers = 0
    public private(set) var startCell: GridPoint?
    /// Letzte Ereignisse für die Anzeige, neueste zuletzt.
    public private(set) var events: [String] = []

    private var byID: [Int: Building] = [:]
    private var occupied: [GridPoint: Int] = [:]
    private var nextBuildingID = 1
    private var nextCarrierID = 1

    public init(data: GameData, terrain: Terrain, foundSettlement: Bool = true) {
        self.data = data
        self.terrain = terrain
        self.money = data.rules.startMoney
        if foundSettlement {
            foundStartSettlement()
        }
    }

    public convenience init(data: GameData, seed: UInt64) {
        self.init(data: data, terrain: Terrain(seed: seed))
    }

    // MARK: - Zeit und Kennzahlen

    public var day: Int { tick / rules.ticksPerDay }
    public var year: Int { day / rules.daysPerYear }
    public var dayOfYear: Int { day % rules.daysPerYear }

    public var population: Int {
        buildings.reduce(0) { $0 + $1.residents }
    }

    public var workersNeeded: Int {
        buildings.reduce(0) { $0 + ($1.definition.category == .production ? $1.definition.workers : 0) }
    }

    public var workersAssigned: Int {
        buildings.reduce(0) { $0 + $1.assignedWorkers }
    }

    /// Summe aller Waren in Lagerhäusern.
    public var storedGoods: [String: Int] {
        var result: [String: Int] = [:]
        for b in buildings where b.definition.category == .storage {
            for item in b.output.sortedItems {
                result[item.good, default: 0] += item.count
            }
        }
        return result
    }

    public func building(id: Int) -> Building? {
        byID[id]
    }

    public func building(at cell: GridPoint) -> Building? {
        occupied[cell].flatMap { byID[$0] }
    }

    // MARK: - Bauen

    /// Prüft, ob ein Gebäude hier stehen darf. Liefert bei Erfolg den Rohstoff-Faktor (0...1).
    public func checkPlacement(_ definition: BuildingDefinition, at cell: GridPoint, ignoreMoney: Bool = false) -> Result<Double, PlacementError> {
        guard terrain.contains(cell) else { return .failure(.outOfBounds) }
        guard terrain.isLand(cell) else { return .failure(.water) }
        let slope = terrain.slopePercent(at: cell)
        guard slope <= rules.maxSlopePercent else { return .failure(.tooSteep(slope)) }
        guard occupied[cell] == nil else { return .failure(.occupied) }
        guard ignoreMoney || money >= definition.cost else { return .failure(.notEnoughMoney(definition.cost)) }
        let factor = resourceFactor(for: definition, at: cell)
        if let resource = definition.resource, factor <= 0 {
            return .failure(.missingResource(resource.biome))
        }
        return .success(factor)
    }

    @discardableResult
    public func place(_ definitionID: String, at cell: GridPoint) -> Result<Building, PlacementError> {
        guard let definition = data.building(definitionID) else { return .failure(.unknownBuilding) }
        switch checkPlacement(definition, at: cell) {
        case .failure(let error):
            return .failure(error)
        case .success(let factor):
            money -= definition.cost
            let building = addBuilding(definition, at: cell, resourceFactor: factor)
            assignWorkers()
            return .success(building)
        }
    }

    /// Reißt ein Gebäude ab. Ein Teil der Baukosten kommt zurück, Waren darin gehen verloren.
    public func demolish(_ id: Int) {
        guard let building = byID[id] else { return }
        buildings.removeAll { $0.id == id }
        byID[id] = nil
        occupied[building.cell] = nil
        money += building.definition.cost * rules.refundPercent / 100

        // Träger auf dem Weg dorthin kehren um; ihre Ladung ist verloren.
        for i in carriers.indices where carriers[i].targetID == id && carriers[i].phase == .delivering {
            carriers[i].phase = .returning
            carriers[i].traveled = max(0, carriers[i].distance - carriers[i].traveled)
        }
        assignWorkers()
        log("\(building.definition.name) abgerissen.")
    }

    /// Anteil passender Kacheln im Umkreis, bezogen auf die ideale Anzahl.
    public func resourceFactor(for definition: BuildingDefinition, at cell: GridPoint) -> Double {
        guard let resource = definition.resource else { return 1 }
        var count = 0
        for dz in -resource.radius...resource.radius {
            for dx in -resource.radius...resource.radius {
                let c = GridPoint(x: cell.x + dx, z: cell.z + dz)
                if c != cell, terrain.contains(c), terrain.biome(at: c) == resource.biome {
                    count += 1
                }
            }
        }
        return min(1, Double(count) / Double(max(1, resource.idealCount)))
    }

    @discardableResult
    private func addBuilding(_ definition: BuildingDefinition, at cell: GridPoint, resourceFactor: Double) -> Building {
        let building = Building(id: nextBuildingID, definition: definition, cell: cell, center: terrain.cellCenter(cell))
        building.resourceFactor = resourceFactor
        nextBuildingID += 1
        buildings.append(building)
        byID[building.id] = building
        occupied[cell] = building.id
        return building
    }

    // MARK: - Startsiedlung

    private func foundStartSettlement() {
        guard
            let storage = data.buildings.first(where: { $0.category == .storage }),
            let house = data.buildings.first(where: { $0.category == .housing }),
            let center = findStartCell()
        else { return }

        startCell = center
        let lager = addBuilding(storage, at: center, resourceFactor: 1)
        for (good, amount) in rules.startStock.sorted(by: { $0.key < $1.key }) {
            lager.output.add(good, amount)
        }

        var placed = 0
        ringLoop: for radius in 2...8 {
            for dz in -radius...radius {
                for dx in -radius...radius where max(abs(dx), abs(dz)) == radius && (dx + dz) % 2 == 0 {
                    guard placed < rules.startHouses else { break ringLoop }
                    let cell = GridPoint(x: center.x + dx, z: center.z + dz)
                    if case .success = checkPlacement(house, at: cell, ignoreMoney: true) {
                        let h = addBuilding(house, at: cell, resourceFactor: 1)
                        h.residents = min(rules.startResidentsPerHouse, house.residents)
                        placed += 1
                    }
                }
            }
        }
        assignWorkers()
        log("Eine neue Siedlung wurde gegründet.")
    }

    /// Sucht vom Kartenmittelpunkt aus eine flache Landfläche (5 × 5 Kacheln).
    private func findStartCell() -> GridPoint? {
        let mid = terrain.size / 2
        for radius in 0..<(terrain.size / 2 - 3) {
            for dz in -radius...radius {
                for dx in -radius...radius where max(abs(dx), abs(dz)) == radius {
                    let c = GridPoint(x: mid + dx, z: mid + dz)
                    if isGoodStartArea(c) {
                        return c
                    }
                }
            }
        }
        return nil
    }

    private func isGoodStartArea(_ center: GridPoint) -> Bool {
        for dz in -2...2 {
            for dx in -2...2 {
                let c = GridPoint(x: center.x + dx, z: center.z + dz)
                guard terrain.isLand(c), terrain.biome(at: c) != .rock, terrain.slopePercent(at: c) <= 15 else {
                    return false
                }
            }
        }
        return true
    }

    // MARK: - Simulationsschritt

    /// Ein Tick. Bei 1× laufen 10 Ticks pro Sekunde.
    public func step() {
        tick += 1
        let ticksPerDay = rules.ticksPerDay

        if tick % ticksPerDay == 0 {
            assignWorkers()
        }
        updateProduction()
        if tick % max(1, rules.dispatchIntervalTicks) == 0 {
            dispatchCarriers()
        }
        moveCarriers()
        if tick % (ticksPerDay * rules.supplyCheckDays) == 0 {
            updateHouses()
        }
        if tick % (ticksPerDay * rules.daysPerYear) == 0 {
            yearlyFinances()
        }
    }

    public func step(ticks: Int) {
        for _ in 0..<max(0, ticks) {
            step()
        }
    }

    public func advance(days: Int) {
        step(ticks: days * rules.ticksPerDay)
    }

    // MARK: - Arbeit

    /// Verteilt die Bewohner auf die Betriebe, älteste Betriebe zuerst.
    private func assignWorkers() {
        var available = population
        for b in buildings {
            guard b.definition.category == .production else { continue }
            let n = min(b.definition.workers, available)
            b.assignedWorkers = n
            available -= n
        }
        freeWorkers = available
    }

    private func updateProduction() {
        let ticksPerDay = Double(rules.ticksPerDay)
        for b in buildings {
            switch b.definition.category {
            case .housing:
                b.status = .housing
            case .storage:
                b.status = .storing
            case .production:
                if b.definition.workers > 0 && b.assignedWorkers == 0 {
                    b.status = .noWorkers
                    continue
                }
                if b.resourceFactor <= 0 {
                    b.status = .noResources
                    continue
                }
                if !b.cycleRunning {
                    let hasRoom = b.definition.outputs.allSatisfy { b.output.space($0.key) >= $0.value }
                    guard hasRoom else {
                        b.status = .outputFull
                        continue
                    }
                    let hasInputs = b.definition.inputs.allSatisfy { b.input.count($0.key) >= $0.value }
                    guard hasInputs else {
                        b.status = .missingInput
                        continue
                    }
                    for (good, amount) in b.definition.inputs {
                        b.input.remove(good, amount)
                    }
                    b.cycleRunning = true
                    b.progress = 0
                }
                b.status = .working
                b.progress += b.efficiency / (max(0.1, b.definition.cycleDays) * ticksPerDay)
                if b.progress >= 1 {
                    for (good, amount) in b.definition.outputs {
                        b.output.add(good, amount)
                    }
                    b.progress = 0
                    b.cycleRunning = false
                }
            }
        }
    }

    // MARK: - Träger

    /// Wie viel von einer Ware das Ziel noch annehmen kann (abzüglich bereits unterwegs).
    private func demand(of target: Building, for good: String) -> Int {
        let incoming = target.incoming[good, default: 0]
        switch target.definition.category {
        case .production:
            guard target.definition.inputs[good] != nil else { return 0 }
            return target.input.space(good) - incoming
        case .housing:
            guard rules.foodGoods.contains(good) else { return 0 }
            return target.input.space(good) - incoming
        case .storage:
            return target.output.space(good) - incoming
        }
    }

    /// Nächstes Ziel im Umkreis. Verbraucher gehen vor, Lagerhäuser nehmen den Rest.
    private func bestTarget(for good: String, from source: Building) -> (building: Building, space: Int)? {
        var best: (building: Building, space: Int, score: Double)?
        for target in buildings where target.id != source.id {
            if source.definition.category == .storage && target.definition.category == .storage {
                continue
            }
            let space = demand(of: target, for: good)
            guard space > 0 else { continue }
            let distance = source.center.distance(to: target.center)
            guard distance <= rules.carrierRadiusMeters else { continue }
            var score = distance
            switch target.definition.category {
            case .storage:
                // Lager nur, wenn kein Verbraucher in Reichweite etwas braucht.
                score += rules.carrierRadiusMeters * 2
            case .housing:
                // Häuser mit wenig Vorrat zuerst, damit nicht immer dasselbe Haus leer ausgeht.
                let stock = rules.foodGoods.reduce(0) { $0 + target.input.count($1) + target.incoming[$1, default: 0] }
                score += Double(stock) * 40
            case .production:
                break
            }
            if best == nil || score < best!.score {
                best = (target, space, score)
            }
        }
        return best.map { ($0.building, $0.space) }
    }

    private func dispatchCarriers() {
        for source in buildings where source.definition.category != .housing {
            var slots = source.definition.maxCarriers - source.carriersOut
            guard slots > 0 else { continue }
            for item in source.output.sortedItems where item.count > 0 {
                guard slots > 0 else { break }
                guard let target = bestTarget(for: item.good, from: source) else { continue }
                let amount = min(rules.carrierCapacity, item.count, target.space)
                guard amount > 0 else { continue }

                source.output.remove(item.good, amount)
                target.building.incoming[item.good, default: 0] += amount
                source.carriersOut += 1
                slots -= 1

                let carrier = Carrier(
                    id: nextCarrierID,
                    good: item.good,
                    amount: amount,
                    sourceID: source.id,
                    targetID: target.building.id,
                    from: source.center,
                    to: target.building.center,
                    distance: source.center.distance(to: target.building.center)
                )
                nextCarrierID += 1
                carriers.append(carrier)
            }
        }
    }

    private func moveCarriers() {
        let stepLength = rules.carrierSpeedMetersPerDay / Double(rules.ticksPerDay)
        var finished = Set<Int>()
        for i in carriers.indices {
            carriers[i].traveled += stepLength
            guard carriers[i].traveled >= carriers[i].distance else { continue }
            switch carriers[i].phase {
            case .delivering:
                deliver(carriers[i])
                carriers[i].phase = .returning
                carriers[i].traveled = 0
            case .returning:
                finished.insert(carriers[i].id)
                if let source = byID[carriers[i].sourceID] {
                    source.carriersOut = max(0, source.carriersOut - 1)
                }
            }
        }
        if !finished.isEmpty {
            carriers.removeAll { finished.contains($0.id) }
        }
    }

    private func deliver(_ carrier: Carrier) {
        guard let target = byID[carrier.targetID] else { return }
        target.incoming[carrier.good] = max(0, target.incoming[carrier.good, default: 0] - carrier.amount)
        switch target.definition.category {
        case .storage:
            target.output.add(carrier.good, carrier.amount)
        case .production, .housing:
            target.input.add(carrier.good, carrier.amount)
        }
    }

    // MARK: - Bewohner

    private func updateHouses() {
        for house in buildings where house.definition.category == .housing {
            let hasFood = rules.foodGoods.contains { house.input.count($0) > 0 }

            if house.residents == 0 {
                // Leere Häuser werden wieder bezogen, sobald Essen da ist.
                if hasFood {
                    house.residents = 1
                    house.lastSupply = 1
                } else {
                    house.lastSupply = 0
                }
                continue
            }

            let need = Double(house.residents) * rules.foodPerResidentPerCheck
            house.foodOwed += need
            var eaten = 0.0
            while house.foodOwed >= 1, let good = rules.foodGoods.first(where: { house.input.count($0) > 0 }) {
                house.input.remove(good, 1)
                house.foodOwed -= 1
                eaten += 1
            }
            // Blieb mehr als eine Einheit offen, war nicht genug Essen da.
            let starving = house.foodOwed >= 1
            let supply = starving ? min(1, eaten / need) : 1
            // Keine Schulden aufbauen: was heute fehlt, ist verloren.
            house.foodOwed = min(house.foodOwed, 0.99)
            house.lastSupply = supply

            if supply >= 0.9 && house.residents < house.definition.residents {
                house.residents += 1
            } else if supply < 0.5 {
                house.residents -= 1
                log("Hunger: Ein Bewohner ist weggezogen.")
            }
        }
        assignWorkers()
    }

    // MARK: - Finanzen

    private func yearlyFinances() {
        var taxes = 0
        var upkeep = 0
        for b in buildings {
            upkeep += b.definition.upkeepPerYear
            if b.lastSupply >= 0.5 {
                taxes += b.residents * rules.taxPerResidentPerYear
            }
        }
        money += taxes - upkeep
        log("Jahr \(year): +\(taxes) Taler Steuern, −\(upkeep) Taler Unterhalt.")
    }

    private func log(_ message: String) {
        events.append(message)
        if events.count > 20 {
            events.removeFirst(events.count - 20)
        }
    }
}
