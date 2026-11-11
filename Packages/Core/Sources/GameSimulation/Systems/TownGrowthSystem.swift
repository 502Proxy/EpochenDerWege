import GameDomain

/// Lets towns build houses, markets and workshops in their zones on their own.
///
/// Every `zoneGrowthIntervalDays` the town looks at its ``ZoneDemand``. When the demand
/// of a zone reaches the growth threshold it builds one building there, free of
/// charge, on the best free zoned cell next to a road: closest to the settlement
/// centre first. Housing grows with open jobs or a food surplus; markets and workshops
/// follow the population. New houses start empty and are moved into once carriers
/// deliver food, so growth depends on working logistics.
public struct TownGrowthSystem: SimulationSystem {
    public init() {}

    public func update(_ world: inout WorldState) {
        guard world.clock.isStartOfPeriod(days: world.rules.zoneGrowthIntervalDays) else { return }

        if ZoneDemand.residential(in: world).isGrowing, let house = world.catalog.firstBuilding(of: .housing) {
            build(house, in: .residential, world: &world)
        }
        for kind in [ZoneKind.commercial, .industrial] {
            for definition in world.catalog.buildings(forZone: kind) where Self.wantsAnother(definition, in: world) {
                build(definition, in: kind, world: &world)
            }
        }
    }

    private func build(_ definition: BuildingDefinition, in zone: ZoneKind, world: inout WorldState) {
        guard let cell = Self.bestBuildingSite(for: definition, in: zone, world: world) else { return }
        let id = world.addBuilding(definition, at: cell, resourceFactor: 1)
        world.emit(.townGrew(id))
    }

    /// Whether the town supports another commerce building of this type.
    static func wantsAnother(_ definition: BuildingDefinition, in world: WorldState) -> Bool {
        (definition.requiredLevel ?? 0) <= world.settlementLevel
            && ZoneDemand.commerceValue(for: definition, in: world) >= ZoneDemand.growthThreshold
    }

    /// The free cell of a zone next to a road that is closest to the settlement centre.
    static func bestBuildingSite(for definition: BuildingDefinition, in zone: ZoneKind, world: WorldState) -> GridPoint? {
        let center = world.startCell ?? GridPoint(x: world.terrain.size / 2, z: world.terrain.size / 2)
        var best: (cell: GridPoint, score: Int)?
        for (cell, kind) in world.zones where kind == zone {
            guard isNextToRoad(cell, in: world),
                  case .success = PlacementValidator.validate(definition, at: cell, in: world, ignoringCost: true)
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
