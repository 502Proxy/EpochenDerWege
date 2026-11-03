import GameDomain

/// Lets towns build houses in residential zones on their own.
///
/// Every `zoneGrowthIntervalDays` the town checks its demand. It grows when jobs are
/// open, or when enough food is stored and the existing houses are well supplied. It
/// then builds one house, free of charge, on the best free zoned cell next to a road:
/// closest to the settlement centre first. New houses start empty and are moved into
/// once carriers deliver food, so growth depends on working logistics.
public struct TownGrowthSystem: SimulationSystem {
    /// Average supply of existing houses required before food alone drives growth.
    public static let requiredSupply = 0.75

    public init() {}

    public func update(_ world: inout WorldState) {
        guard world.clock.isStartOfPeriod(days: world.rules.zoneGrowthIntervalDays) else { return }
        guard Self.hasHousingDemand(in: world),
              let house = world.catalog.firstBuilding(of: .housing),
              let cell = Self.bestBuildingSite(for: house, in: world)
        else { return }

        let id = world.addBuilding(house, at: cell, resourceFactor: 1)
        world.emit(.townGrew(id))
    }

    /// Whether the town wants another house.
    static func hasHousingDemand(in world: WorldState) -> Bool {
        let houses = world.buildings.filter { $0.category == .housing }
        // Do not build ahead of demand: wait until empty houses are moved into.
        guard !houses.contains(where: { $0.residents == 0 }) else { return false }
        if world.workersNeeded > world.population {
            return true
        }
        let storedFood = world.rules.foodGoods.reduce(0) { $0 + world.storedAmount(of: $1) }
        let averageSupply = houses.isEmpty ? 1 : houses.reduce(0) { $0 + $1.supplyRatio } / Double(houses.count)
        return storedFood >= world.rules.zoneGrowthFoodThreshold && averageSupply >= requiredSupply
    }

    /// The free residential cell next to a road that is closest to the settlement centre.
    static func bestBuildingSite(for house: BuildingDefinition, in world: WorldState) -> GridPoint? {
        let center = world.startCell ?? GridPoint(x: world.terrain.size / 2, z: world.terrain.size / 2)
        var best: (cell: GridPoint, score: Int)?
        for (cell, kind) in world.zones where kind == .residential {
            guard isNextToRoad(cell, in: world),
                  case .success = PlacementValidator.validate(house, at: cell, in: world, ignoringCost: true)
            else { continue }
            let dx = cell.x - center.x
            let dz = cell.z - center.z
            let score = dx * dx + dz * dz
            // Ties are broken by position so the choice never depends on dictionary order.
            if let current = best, (score, cell.z, cell.x) >= (current.score, current.cell.z, current.cell.x) {
                continue
            }
            best = (cell, score)
        }
        return best?.cell
    }

    static func isNextToRoad(_ cell: GridPoint, in world: WorldState) -> Bool {
        [cell.offset(dx: 1, dz: 0), cell.offset(dx: -1, dz: 0), cell.offset(dx: 0, dz: 1), cell.offset(dx: 0, dz: -1)]
            .contains(where: world.hasRoad(at:))
    }
}
