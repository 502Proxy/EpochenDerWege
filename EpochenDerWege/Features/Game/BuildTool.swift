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
    /// Click stops one after another to create a line.
    case line

    /// Whether dragging with this tool marks an area instead of moving the map.
    var drawsArea: Bool {
        switch self {
        case .road, .zone, .unzone: true
        case .building, .bulldoze, .line: false
        }
    }
}

/// Groups of tools in the build toolbar.
enum ToolCategory: String, CaseIterable, Identifiable {
    case transport
    case zones
    case production
    case storage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transport: String(localized: "Transport")
        case .zones: String(localized: "Zones")
        case .production: String(localized: "Production")
        case .storage: String(localized: "Storage")
        }
    }

    var symbol: String {
        switch self {
        case .transport: "road.lanes"
        case .zones: "square.grid.3x3.fill"
        case .production: "hammer.fill"
        case .storage: "shippingbox.fill"
        }
    }

    /// Keyboard shortcut that opens the category.
    var shortcut: Character {
        switch self {
        case .transport: "1"
        case .zones: "2"
        case .production: "3"
        case .storage: "4"
        }
    }

    /// Tools in this category, in display order.
    func tools(in catalog: GameCatalog) -> [BuildTool] {
        switch self {
        case .transport:
            [.road] + catalog.buildings.filter { $0.category == .stop }.map { .building($0.id) } + [.line, .bulldoze]
        case .zones:
            // Houses, markets and workshops are built by the towns themselves inside zones.
            ZoneKind.allCases.map { .zone($0) } + [.unzone]
        case .production:
            catalog.buildings.filter { $0.category == .production }.map { .building($0.id) }
        case .storage:
            catalog.buildings.filter { $0.category == .storage }.map { .building($0.id) }
        }
    }

    /// The category a tool belongs to.
    static func of(_ tool: BuildTool, in catalog: GameCatalog) -> ToolCategory {
        switch tool {
        case .road, .bulldoze, .line:
            return .transport
        case .zone, .unzone:
            return .zones
        case .building(let type):
            switch catalog.building(type)?.category {
            case .housing, .commerce: return .zones
            case .stop: return .transport
            case .storage: return .storage
            default: return .production
            }
        }
    }
}
