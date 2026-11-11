import GameDomain

/// Decides whether a building may be placed on a cell.
///
/// Pure function of the world state, so the app can use it for the live placement
/// preview on the main thread while the simulation runs in the background.
public enum PlacementValidator {
    /// Validates a placement and returns the resource factor (`0...1`) on success.
    public static func validate(
        _ definition: BuildingDefinition,
        at cell: GridPoint,
        in world: WorldState,
        ignoringCost: Bool = false
    ) -> Result<Double, PlacementError> {
        let terrain = world.terrain
        if let level = definition.requiredLevel, level > world.settlementLevel {
            return .failure(.requiresLevel(level))
        }
        guard terrain.contains(cell) else { return .failure(.outOfBounds) }
        guard terrain.isLand(cell) else { return .failure(.water) }
        let slope = terrain.slopePercent(at: cell)
        guard slope <= world.rules.maxSlopePercent else { return .failure(.tooSteep(slopePercent: slope)) }
        guard !world.isOccupied(cell), !world.hasRoad(at: cell) else { return .failure(.occupied) }
        if let zones = definition.allowedZones, !zones.isEmpty {
            guard let zone = world.zones[cell], zones.contains(zone) else { return .failure(.requiresZone(zones)) }
        }
        if definition.requiresRoadAccess == true {
            let neighbours = [cell.offset(dx: 1, dz: 0), cell.offset(dx: -1, dz: 0), cell.offset(dx: 0, dz: 1), cell.offset(dx: 0, dz: -1)]
            guard neighbours.contains(where: { world.hasRoad(at: $0) && !world.tunnels.contains($0) }) else {
                return .failure(.noRoadAccess)
            }
        }
        guard ignoringCost || world.treasury >= definition.cost else {
            return .failure(.insufficientFunds(cost: definition.cost))
        }
        let factor = resourceFactor(for: definition, at: cell, on: terrain)
        if let resource = definition.resource, factor <= 0 {
            return .failure(.missingResource(resource.biome))
        }
        return .success(factor)
    }

    /// Share of matching resource cells around `cell`, relative to the ideal count.
    public static func resourceFactor(for definition: BuildingDefinition, at cell: GridPoint, on terrain: Terrain) -> Double {
        guard let resource = definition.resource else { return 1 }
        var count = 0
        for dz in -resource.radius...resource.radius {
            for dx in -resource.radius...resource.radius where dx != 0 || dz != 0 {
                let neighbour = cell.offset(dx: dx, dz: dz)
                if terrain.contains(neighbour) && terrain.biome(at: neighbour) == resource.biome {
                    count += 1
                }
            }
        }
        return min(1, Double(count) / Double(max(1, resource.idealCount)))
    }
}
