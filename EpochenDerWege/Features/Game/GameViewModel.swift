import GameDomain
import GameSimulation
import Observation

/// Values shown in the top bar.
struct HUDState: Equatable {
    var year = 0
    var dayOfYear = 0
    var treasury = 0
    var population = 0
    var workersEmployed = 0
    var workersNeeded = 0
    var unemployed = 0
    var carriers = 0
    var stock: [StockItem] = []

    struct StockItem: Equatable, Identifiable {
        let id: GoodID
        let name: String
        let amount: Int
    }
}

/// A short message at the bottom of the screen.
struct Toast: Equatable, Identifiable {
    let id: Int
    let text: String
}

/// Presentation state and user intents for the game screen (MVVM).
///
/// The view model never mutates the world directly. It reads immutable snapshots
/// from the engine and sends commands back. The HUD refreshes a few times per
/// second; the 3D scene reads snapshots every frame on its own.
@Observable
final class GameViewModel {
    private(set) var hud = HUDState()
    private(set) var selectedTool: BuildTool?
    private(set) var selectedBuildingID: BuildingID?
    private(set) var inspector: BuildingDetails?
    private(set) var toast: Toast?
    private(set) var speed: Int
    private(set) var finances = FinanceSummary()

    let catalog: GameCatalog

    @ObservationIgnored private let engine: SimulationEngine
    @ObservationIgnored private var lastHandledEvent = 0
    @ObservationIgnored private var toastExpiry: ContinuousClock.Instant?

    static let refreshInterval: Duration = .milliseconds(200)
    static let toastDuration: Duration = .seconds(4)

    init(engine: SimulationEngine) {
        self.engine = engine
        let world = engine.snapshots.value.world
        catalog = world.catalog
        speed = engine.speed
        refresh(with: world)
    }

    /// Latest world snapshot. Not observed; read it when you need it.
    var world: WorldState {
        engine.snapshots.value.world
    }

    /// Refreshes the HUD until the surrounding task is cancelled. Call from `.task`.
    func run() async {
        while !Task.isCancelled {
            refresh(with: world)
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    // MARK: - Intents

    /// Selects a tool; selecting the active tool again deselects it.
    func toggleTool(_ tool: BuildTool) {
        selectedTool = selectedTool == tool ? nil : tool
        if selectedTool != nil {
            selectBuilding(nil)
        }
    }

    /// The building type of the active tool, if it places buildings.
    var selectedBuildingType: BuildingTypeID? {
        if case .building(let type) = selectedTool { type } else { nil }
    }

    func selectBuilding(_ id: BuildingID?) {
        selectedBuildingID = id
        refresh(with: world)
    }

    /// Escape or right click: drop the tool first, then the selection.
    func cancel() {
        if selectedTool != nil {
            selectedTool = nil
        } else {
            selectBuilding(nil)
        }
    }

    func click(on cell: GridPoint?) {
        guard let cell else { return }
        switch selectedTool {
        case .building(let type):
            engine.submit(PlaceBuildingCommand(buildingType: type, cell: cell))
        case .road:
            engine.submit(BuildRoadCommand(cells: [cell]))
        case .zone(let kind):
            engine.submit(ZoneCommand(cells: [cell], kind: kind))
        case .unzone:
            engine.submit(ZoneCommand(cells: [cell], kind: nil))
        case .bulldoze:
            let world = world
            if let building = world.building(at: cell) {
                engine.submit(DemolishBuildingCommand(buildingID: building.id))
            } else if world.hasRoad(at: cell) {
                engine.submit(DemolishRoadCommand(cells: [cell]))
            }
        case nil:
            selectBuilding(world.building(at: cell)?.id)
        }
    }

    /// Finishes a drag with an area tool: road along an L-shaped path, zoning on a rectangle.
    func applyDrag(from start: GridPoint, to end: GridPoint) {
        switch selectedTool {
        case .road:
            engine.submit(BuildRoadCommand(cells: RoadPlanner.path(from: start, to: end)))
        case .zone(let kind):
            engine.submit(ZoneCommand(cells: ZonePlanner.rectangle(from: start, to: end), kind: kind))
        case .unzone:
            engine.submit(ZoneCommand(cells: ZonePlanner.rectangle(from: start, to: end), kind: nil))
        case .building, .bulldoze, nil:
            break
        }
    }

    func demolishSelected() {
        guard let selectedBuildingID else { return }
        engine.submit(DemolishBuildingCommand(buildingID: selectedBuildingID))
        selectBuilding(nil)
    }

    func setSpeed(_ multiplier: Int) {
        engine.setSpeed(multiplier)
        speed = engine.speed
    }

    func togglePause() {
        setSpeed(speed == 0 ? 1 : 0)
    }

    /// Placement preview for the scene: `nil` without a tool, otherwise whether the cell is valid.
    func previewValidity(at cell: GridPoint, in world: WorldState) -> Bool? {
        guard let type = selectedBuildingType, let definition = catalog.building(type) else { return nil }
        if case .success = PlacementValidator.validate(definition, at: cell, in: world) {
            return true
        }
        return false
    }

    // MARK: - Refresh

    private func refresh(with world: WorldState) {
        var next = HUDState()
        next.year = world.clock.year
        next.dayOfYear = world.clock.dayOfYear
        next.treasury = world.treasury
        next.population = world.population
        next.workersEmployed = world.workersEmployed
        next.workersNeeded = world.workersNeeded
        next.unemployed = world.unemployed
        next.carriers = world.carriers.count
        next.stock = world.storedGoods.map {
            HUDState.StockItem(id: $0.good, name: GameText.goodName($0.good, in: catalog), amount: $0.amount)
        }
        if next != hud {
            hud = next
        }
        let summary = FinanceSummary(world: world)
        if summary != finances {
            finances = summary
        }

        let details = selectedBuildingID
            .flatMap { world.building($0) }
            .map { BuildingDetails(building: $0, world: world) }
        if details != inspector {
            inspector = details
        }
        if selectedBuildingID != nil && details == nil {
            // The selected building no longer exists.
            selectedBuildingID = nil
        }

        handleNewEvents(in: world)
    }

    private func handleNewEvents(in world: WorldState) {
        let now = ContinuousClock.now
        for record in world.events where record.sequence > lastHandledEvent {
            lastHandledEvent = record.sequence
            if let text = GameText.message(for: record.event, catalog: catalog) {
                toast = Toast(id: record.sequence, text: text)
                toastExpiry = now + Self.toastDuration
            }
        }
        if let toastExpiry, now >= toastExpiry {
            toast = nil
            self.toastExpiry = nil
        }
    }
}
