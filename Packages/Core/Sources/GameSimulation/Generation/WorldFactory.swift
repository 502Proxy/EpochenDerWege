import GameDomain

/// Creates new worlds (factory pattern): terrain plus a starting settlement.
public enum WorldFactory {
    /// Generates terrain from a seed and founds a settlement near the map centre.
    public static func makeWorld(catalog: GameCatalog, seed: UInt64, mapSize: Int = 128) -> WorldState {
        let terrain = TerrainGenerator(seed: seed, size: mapSize).generate()
        return makeWorld(catalog: catalog, terrain: terrain)
    }

    /// Builds a world on existing terrain.
    public static func makeWorld(catalog: GameCatalog, terrain: Terrain, foundSettlement: Bool = true) -> WorldState {
        var world = WorldState(catalog: catalog, terrain: terrain)
        if foundSettlement {
            SettlementFounder.found(in: &world)
        }
        return world
    }
}

/// Places the starting storehouse and houses.
enum SettlementFounder {
    static func found(in world: inout WorldState) {
        let catalog = world.catalog
        guard
            let storehouse = catalog.firstBuilding(of: .storage),
            let house = catalog.firstBuilding(of: .housing),
            let center = findStartCell(on: world.terrain)
        else { return }

        world.startCell = center
        let storehouseID = world.addBuilding(storehouse, at: center, resourceFactor: 1)
        if let index = world.index(of: storehouseID) {
            for stock in world.rules.startingStock {
                world.buildings[index].output.add(stock.good, amount: stock.amount)
            }
        }

        // Houses on every other cell of the rings around the storehouse, leaving the
        // inner ring free for the player's first production buildings.
        var placed = 0
        search: for radius in 2...8 {
            for dz in -radius...radius {
                for dx in -radius...radius where max(abs(dx), abs(dz)) == radius && (dx + dz) % 2 == 0 {
                    guard placed < world.rules.startingHouses else { break search }
                    let cell = center.offset(dx: dx, dz: dz)
                    guard case .success = PlacementValidator.validate(house, at: cell, in: world, ignoringCost: true) else {
                        continue
                    }
                    let id = world.addBuilding(house, at: cell, resourceFactor: 1)
                    if let index = world.index(of: id) {
                        world.buildings[index].residents = min(world.rules.startingResidentsPerHouse, house.maxResidents)
                    }
                    placed += 1
                }
            }
        }

        WorkforceSystem.assignWorkers(in: &world)
        world.emit(.settlementFounded(population: world.population))
    }

    /// Searches outwards from the map centre for a flat 5 × 5 area of usable land.
    static func findStartCell(on terrain: Terrain) -> GridPoint? {
        let middle = GridPoint(x: terrain.size / 2, z: terrain.size / 2)
        for radius in 0..<max(1, terrain.size / 2 - 3) {
            for dz in -radius...radius {
                for dx in -radius...radius where max(abs(dx), abs(dz)) == radius {
                    let cell = middle.offset(dx: dx, dz: dz)
                    if isSuitableStart(cell, on: terrain) {
                        return cell
                    }
                }
            }
        }
        return nil
    }

    private static func isSuitableStart(_ center: GridPoint, on terrain: Terrain) -> Bool {
        for dz in -2...2 {
            for dx in -2...2 {
                let cell = center.offset(dx: dx, dz: dz)
                guard
                    terrain.contains(cell),
                    terrain.isLand(cell),
                    terrain.biome(at: cell) != .rock,
                    terrain.slopePercent(at: cell) <= 15
                else { return false }
            }
        }
        return true
    }
}
