import GameDomain

/// What a click or drag on the map does.
enum BuildTool: Hashable {
    /// Place a building of this type.
    case building(BuildingTypeID)
    /// Drag to build gravel road.
    case road
    /// Remove buildings and roads.
    case bulldoze
    /// Drag a rectangle to zone cells; the town builds there on its own.
    case zone(ZoneKind)
    /// Drag a rectangle to remove zoning.
    case unzone

    /// Whether dragging with this tool marks an area instead of moving the map.
    var drawsArea: Bool {
        switch self {
        case .road, .zone, .unzone: true
        case .building, .bulldoze: false
        }
    }
}

/// Groups of tools in the build toolbar.
enum ToolCategory: String, CaseIterable, Identifiable {
    case roads
    case housing
    case production
    case storage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .roads: String(localized: "Roads")
        case .housing: String(localized: "Housing")
        case .production: String(localized: "Production")
        case .storage: String(localized: "Storage")
        }
    }

    var symbol: String {
        switch self {
        case .roads: "road.lanes"
        case .housing: "house.fill"
        case .production: "hammer.fill"
        case .storage: "shippingbox.fill"
        }
    }

    /// Keyboard shortcut that opens the category.
    var shortcut: Character {
        switch self {
        case .roads: "1"
        case .housing: "2"
        case .production: "3"
        case .storage: "4"
        }
    }

    /// Tools in this category, in display order.
    func tools(in catalog: GameCatalog) -> [BuildTool] {
        switch self {
        case .roads:
            [.road, .bulldoze]
        case .housing:
            // Houses are built by the towns themselves inside residential zones.
            [.zone(.residential), .unzone]
        case .production:
            catalog.buildings.filter { $0.category == .production }.map { .building($0.id) }
        case .storage:
            catalog.buildings.filter { $0.category == .storage }.map { .building($0.id) }
        }
    }

    /// The category a tool belongs to.
    static func of(_ tool: BuildTool, in catalog: GameCatalog) -> ToolCategory {
        switch tool {
        case .road, .bulldoze:
            return .roads
        case .zone, .unzone:
            return .housing
        case .building(let type):
            switch catalog.building(type)?.category {
            case .housing: return .housing
            case .storage: return .storage
            default: return .production
            }
        }
    }
}
