import GameDomain
import GameSimulation

/// One good in the goods overview.
struct GoodRow: Equatable, Identifiable {
    let id: GoodID
    let name: String
    let color: GameColor
    let producedThisYear: Int
    let consumedThisYear: Int
    let producedLastYear: Int
    let consumedLastYear: Int
    /// Everything that exists: in buildings, on carriers and on vehicles.
    let inStock: Int
    let salesThisYear: Int

    /// Production minus consumption this year; negative means shortage.
    var balanceThisYear: Int { producedThisYear - consumedThisYear }

    static func make(for world: WorldState) -> [GoodRow] {
        let year = world.clock.year
        let account = world.ledger.account(forYear: year)
        return world.catalog.goods.map { good in
            let current = world.goodsStatistics.flow(of: good.id, year: year)
            let previous = world.goodsStatistics.flow(of: good.id, year: year - 1)
            return GoodRow(
                id: good.id,
                name: GameText.goodName(good.id, in: world.catalog),
                color: good.color,
                producedThisYear: current.produced,
                consumedThisYear: current.consumed,
                producedLastYear: previous.produced,
                consumedLastYear: previous.consumed,
                inStock: world.totalAmount(of: good.id),
                salesThisYear: account.total(for: .sales, detail: .good(good.id))
            )
        }
    }
}

/// One building in the building list.
///
/// `nonisolated` and `Sendable` because the table sorts it with key-path comparators,
/// which Swift 6 requires to be sendable.
nonisolated struct BuildingRow: Equatable, Identifiable, Sendable {
    let id: BuildingID
    let name: String
    let category: BuildingCategory
    let status: String
    let tone: StatusTone
    /// "2 / 6", or empty for buildings without workers.
    let workers: String
    /// Efficiency in `0...1`, or `nil` where it does not apply.
    let efficiency: Double?
    let cell: GridPoint

    /// Sort key for the efficiency column; buildings without one go last.
    var efficiencySortKey: Double { efficiency ?? -1 }

    @MainActor
    static func make(for world: WorldState) -> [BuildingRow] {
        // Towns' stops are not the player's buildings.
        world.buildings.filter { $0.townID == nil }.map { building in
            let status = GameText.status(of: building)
            let isProduction = building.category == .production
            return BuildingRow(
                id: building.id,
                name: building.category == .stop
                    ? GameText.stopName(building.id, in: world)
                    : GameText.name(of: building.definition),
                category: building.category,
                status: status.text,
                tone: status.tone,
                workers: building.definition.workers > 0 ? "\(building.assignedWorkers) / \(building.definition.workers)" : "",
                efficiency: isProduction ? building.efficiency : nil,
                cell: building.cell
            )
        }
    }
}

/// A request to move the camera to a cell. The id makes repeated requests distinguishable.
struct CameraFocus: Equatable {
    let id: Int
    let cell: GridPoint
}
