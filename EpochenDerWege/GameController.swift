import Foundation
import Observation
import Simulation

/// Werte für die obere Leiste. Wird ein paar Mal pro Sekunde aktualisiert, nicht jeden Frame.
struct HUDSnapshot {
    var year = 0
    var dayOfYear = 0
    var money = 0
    var population = 0
    var workersAssigned = 0
    var workersNeeded = 0
    var freeWorkers = 0
    var carriers = 0
    var stock: [(name: String, count: Int)] = []
}

/// Anzeige für ein ausgewähltes Gebäude.
struct BuildingInfo {
    var id: Int
    var name: String
    var status: String
    var statusLevel: StatusLevel
    var rows: [(label: String, value: String)]

    enum StatusLevel {
        case good, warning, problem, neutral
    }
}

/// Verbindet Simulation, Eingaben und Oberfläche.
@MainActor
@Observable
final class GameController {
    let simulation: Simulation

    /// 0 = Pause, sonst Zeitraffer-Faktor.
    var speed = 1
    /// Gewähltes Bauwerkzeug (ID aus den Spieldaten) oder nil zum Auswählen.
    private(set) var selectedTool: String?
    private(set) var selectedBuildingID: Int?
    private(set) var message: String?

    private(set) var hud = HUDSnapshot()
    private(set) var inspector: BuildingInfo?

    @ObservationIgnored private var tickAccumulator = 0.0
    @ObservationIgnored private var hudTimer = 0.0
    @ObservationIgnored private var messageAge = 0.0
    @ObservationIgnored private var lastEventCount = 0

    /// Design: 10 Ticks pro Sekunde bei 1×.
    static let ticksPerSecond = 10.0

    init(seed: UInt64 = 2026) {
        let data: GameData
        do {
            data = try GameData.loadDefault()
        } catch {
            fatalError("Spieldaten konnten nicht geladen werden: \(error)")
        }
        simulation = Simulation(data: data, seed: seed)
        lastEventCount = simulation.events.count
        refreshHUD()
    }

    var buildingDefinitions: [BuildingDefinition] {
        simulation.data.buildings
    }

    // MARK: - Spielschleife

    /// Wird jeden Frame von der 3D-Ansicht aufgerufen.
    func advance(deltaTime dt: Double) {
        if speed > 0 {
            tickAccumulator += dt * GameController.ticksPerSecond * Double(speed)
            var ticks = Int(tickAccumulator)
            tickAccumulator -= Double(ticks)
            // Nach einem Hänger nicht hunderte Ticks auf einmal nachholen.
            ticks = min(ticks, 40)
            for _ in 0..<ticks {
                simulation.step()
            }
        }

        if simulation.events.count != lastEventCount {
            lastEventCount = simulation.events.count
            if let last = simulation.events.last {
                showMessage(last)
            }
        }

        if message != nil {
            messageAge += dt
            if messageAge > 5 {
                message = nil
            }
        }

        hudTimer += dt
        if hudTimer >= 0.25 {
            hudTimer = 0
            refreshHUD()
        }
    }

    /// Wählt ein Bauwerkzeug; ein zweiter Klick auf dasselbe legt es wieder ab.
    func toggleTool(_ id: String) {
        selectedTool = selectedTool == id ? nil : id
        if selectedTool != nil {
            select(buildingID: nil)
        }
    }

    func select(buildingID: Int?) {
        selectedBuildingID = buildingID
        refreshHUD()
    }

    func togglePause() {
        speed = speed == 0 ? 1 : 0
    }

    // MARK: - Eingaben

    func handleClick(on cell: GridPoint?) {
        guard let cell else { return }
        if let tool = selectedTool {
            switch simulation.place(tool, at: cell) {
            case .success(let building):
                showMessage("\(building.definition.name) gebaut (−\(building.definition.cost) Taler).")
            case .failure(let error):
                showMessage(error.message)
            }
        } else {
            select(buildingID: simulation.building(at: cell)?.id)
        }
        refreshHUD()
    }

    func cancelTool() {
        if selectedTool != nil {
            selectedTool = nil
        } else {
            select(buildingID: nil)
        }
    }

    func demolishSelected() {
        guard let id = selectedBuildingID else { return }
        simulation.demolish(id)
        select(buildingID: nil)
    }

    func placementCheck(for cell: GridPoint) -> Bool? {
        guard let tool = selectedTool, let definition = simulation.data.building(tool) else { return nil }
        if case .success = simulation.checkPlacement(definition, at: cell) {
            return true
        }
        return false
    }

    private func showMessage(_ text: String) {
        message = text
        messageAge = 0
    }

    // MARK: - Anzeige

    func refreshHUD() {
        let sim = simulation
        var snapshot = HUDSnapshot()
        snapshot.year = sim.year
        snapshot.dayOfYear = sim.dayOfYear
        snapshot.money = sim.money
        snapshot.population = sim.population
        snapshot.workersAssigned = sim.workersAssigned
        snapshot.workersNeeded = sim.workersNeeded
        snapshot.freeWorkers = sim.freeWorkers
        snapshot.carriers = sim.carriers.count
        snapshot.stock = sim.storedGoods
            .sorted { $0.key < $1.key }
            .map { (name: sim.data.goodName($0.key), count: $0.value) }
        hud = snapshot

        if let id = selectedBuildingID, let building = sim.building(id: id) {
            inspector = makeInfo(building)
        } else {
            inspector = nil
        }
    }

    private func makeInfo(_ b: Building) -> BuildingInfo {
        let data = simulation.data
        var rows: [(label: String, value: String)] = []

        switch b.definition.category {
        case .production:
            rows.append(("Arbeiter", "\(b.assignedWorkers) / \(b.definition.workers)"))
            if b.definition.resource != nil {
                rows.append(("Rohstoffe in Reichweite", percent(b.resourceFactor)))
            }
            rows.append(("Leistung", percent(b.efficiency)))
            if b.cycleRunning {
                rows.append(("Fortschritt", percent(b.progress)))
            }
            for (good, amount) in b.definition.inputs.sorted(by: { $0.key < $1.key }) {
                rows.append(("Braucht \(data.goodName(good))", "\(b.input.count(good)) / \(b.input.capacityPerGood)  (je \(amount))"))
            }
            for (good, amount) in b.definition.outputs.sorted(by: { $0.key < $1.key }) {
                rows.append(("Erzeugt \(data.goodName(good))", "\(b.output.count(good)) / \(b.output.capacityPerGood)  (je \(amount))"))
            }
            rows.append(("Träger unterwegs", "\(b.carriersOut) / \(b.definition.maxCarriers)"))
        case .storage:
            let items = b.output.sortedItems
            if items.isEmpty {
                rows.append(("Bestand", "leer"))
            }
            for item in items {
                rows.append((data.goodName(item.good), "\(item.count) / \(b.output.capacityPerGood)"))
            }
            rows.append(("Träger unterwegs", "\(b.carriersOut) / \(b.definition.maxCarriers)"))
        case .housing:
            rows.append(("Bewohner", "\(b.residents) / \(b.definition.residents)"))
            rows.append(("Versorgung", percent(b.lastSupply)))
            for good in simulation.rules.foodGoods {
                rows.append(("Vorrat \(data.goodName(good))", "\(b.input.count(good)) / \(b.input.capacityPerGood)"))
            }
        }

        let (status, level) = statusText(for: b)
        return BuildingInfo(id: b.id, name: b.definition.name, status: status, statusLevel: level, rows: rows)
    }

    private func statusText(for b: Building) -> (String, BuildingInfo.StatusLevel) {
        switch b.status {
        case .working:
            return ("Arbeitet", .good)
        case .idle:
            return ("Bereit", .neutral)
        case .missingInput:
            return ("Wartet auf Rohstoffe", .warning)
        case .outputFull:
            return ("Ausgangslager voll – Träger kommen nicht hinterher", .warning)
        case .noWorkers:
            return ("Keine Arbeiter – baue mehr Häuser", .problem)
        case .noResources:
            return ("Keine Rohstoffe in Reichweite", .problem)
        case .storing:
            return ("Lagerhaus", .neutral)
        case .housing:
            if b.residents == 0 {
                return ("Leer – wartet auf Essen", .problem)
            }
            if b.lastSupply >= 0.9 {
                return ("Gut versorgt", .good)
            }
            if b.lastSupply >= 0.5 {
                return ("Knapp versorgt", .warning)
            }
            return ("Hunger", .problem)
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded())) %"
    }
}
