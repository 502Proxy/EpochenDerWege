import GameDomain
import GameSimulation

/// How a status should be presented.
enum StatusTone: Equatable {
    case good, warning, problem, neutral
}

/// Inspector content for one building, already formatted for display.
struct BuildingDetails: Equatable {
    struct Row: Equatable, Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    let id: BuildingID
    let name: String
    let status: String
    let tone: StatusTone
    let rows: [Row]
    /// Whether the player may pause the building and set its priority.
    let isConfigurable: Bool
    let isPaused: Bool
    let priority: DeliveryPriority

    init(building: Building, world: WorldState) {
        let catalog = world.catalog
        let definition = building.definition
        var rows: [Row] = []

        func row(_ label: String, _ value: String) {
            rows.append(Row(label: label, value: value))
        }
        func goodName(_ id: GoodID) -> String {
            GameText.goodName(id, in: catalog)
        }

        switch building.category {
        case .production:
            row(String(localized: "Workers"), "\(building.assignedWorkers) / \(definition.workers)")
            if definition.resource != nil {
                row(String(localized: "Resources in reach"), GameText.percent(building.resourceFactor))
            }
            row(String(localized: "Efficiency"), GameText.percent(building.efficiency))
            if building.isCycleRunning {
                row(String(localized: "Progress"), GameText.percent(building.progress))
            }
            for input in definition.inputs {
                row(String(localized: "Needs \(goodName(input.good))"), "\(building.input.count(of: input.good)) / \(building.input.capacityPerGood)")
            }
            for output in definition.outputs {
                row(String(localized: "Produces \(goodName(output.good))"), "\(building.output.count(of: output.good)) / \(building.output.capacityPerGood)")
            }
            row(String(localized: "Carriers out"), "\(building.activeCarriers) / \(definition.maxCarriers)")
        case .storage:
            let stock = building.output.sortedItems
            if stock.isEmpty {
                row(String(localized: "Stock"), String(localized: "Empty"))
            }
            for item in stock {
                row(goodName(item.good), "\(item.amount) / \(building.output.capacityPerGood)")
            }
            row(String(localized: "Carriers out"), "\(building.activeCarriers) / \(definition.maxCarriers)")
        case .stop:
            let stock = building.output.sortedItems
            if stock.isEmpty {
                row(String(localized: "Waiting goods"), String(localized: "None"))
            }
            for item in stock {
                row(goodName(item.good), "\(item.amount) / \(building.output.capacityPerGood)")
            }
            let lines = world.lines(servingStop: building.id).map { "\($0.number)" }
            row(String(localized: "Lines"), lines.isEmpty ? String(localized: "None") : lines.joined(separator: ", "))
        case .commerce:
            for input in definition.inputs {
                let price = catalog.good(input.good)?.basePrice ?? 0
                row(String(localized: "Buys \(goodName(input.good))"), "\(building.input.count(of: input.good)) / \(building.input.capacityPerGood)  (\(price))")
            }
        case .housing:
            row(String(localized: "Residents"), "\(building.residents) / \(definition.maxResidents)")
            row(String(localized: "Supply"), GameText.percent(building.supplyRatio))
            for good in world.rules.foodGoods {
                row(String(localized: "Food: \(goodName(good))"), "\(building.input.count(of: good)) / \(building.input.capacityPerGood)")
            }
        }

        let status = GameText.status(of: building)
        id = building.id
        name = building.category == .stop ? String(localized: "Stop \(building.id.rawValue)") : GameText.name(of: definition)
        self.status = status.text
        tone = status.tone
        self.rows = rows
        isConfigurable = building.isConfigurable
        isPaused = building.isPaused
        priority = building.priority
    }
}
