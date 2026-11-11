import GameDomain

/// Places what makes the region more than one village: deposits of stone and vines
/// away from the start, and neutral towns further out.
///
/// Everything is placed beyond carrier range of the start, so using it needs roads,
/// stops and lines. Placement is deterministic: the same terrain always yields the
/// same region.
enum RegionPlanner {
    /// Deposits lie this many cells from the start (carriers reach about 19 cells).
    static let depositDistance = 22...45
    /// Towns lie this many cells from the start.
    static let townDistance = 34...60
    static let clustersPerDeposit = 3
    static let maximumTowns = 3
    /// Cells around a town's centre covered by its houses and roads.
    static let townRadius = 3
    /// Proper names for towns; they are not translated.
    static let townNames = ["Aquilon", "Belcastro", "Corvia", "Dunmere", "Esterra", "Falkenau", "Galena", "Hollin"]

    // MARK: - Deposits

    static func addDeposits(to terrain: Terrain, around start: GridPoint) -> Terrain {
        var placed: [GridPoint: Deposit] = [:]
        var centres: [GridPoint] = []
        for deposit in Deposit.allCases {
            let candidates = ringCells(around: start, distance: depositDistance, on: terrain)
                .filter { isBuildable($0, on: terrain) }
                .map { (cell: $0, score: score(of: $0, for: deposit, on: terrain)) }
                .sorted { ($0.score, tieBreak($0.cell)) > ($1.score, tieBreak($1.cell)) }
            var chosen = 0
            for candidate in candidates where chosen < clustersPerDeposit {
                // Keep clusters apart so they spread around the start.
                guard centres.allSatisfy({ distance($0, candidate.cell) >= 16 }) else { continue }
                centres.append(candidate.cell)
                chosen += 1
                for dz in -2...2 {
                    for dx in -2...2 where dx * dx + dz * dz <= 5 {
                        let cell = candidate.cell.offset(dx: dx, dz: dz)
                        if terrain.contains(cell) && terrain.isLand(cell) && terrain.biome(at: cell) != .snow {
                            placed[cell] = deposit
                        }
                    }
                }
            }
        }
        return terrain.addingDeposits(placed)
    }

    /// Stone lies at the foot of rock; vines like gentle grassy slopes.
    private static func score(of cell: GridPoint, for deposit: Deposit, on terrain: Terrain) -> Double {
        switch deposit {
        case .stone:
            var rock = 0
            for dz in -3...3 {
                for dx in -3...3 where terrain.biome(at: cell.offset(dx: dx, dz: dz)) == .rock {
                    rock += 1
                }
            }
            return Double(rock)
        case .vines:
            guard terrain.biome(at: cell) == .grass else { return -100 }
            return -abs(terrain.slopePercent(at: cell) - 15)
        }
    }

    // MARK: - Towns

    /// Founds neighbouring towns: a few roads, a stop that trades and houses around it.
    static func foundTowns(in world: inout WorldState, around start: GridPoint) {
        let catalog = world.catalog
        guard let stop = catalog.firstBuilding(of: .stop), !catalog.townTemplates.isEmpty else { return }
        let terrain = world.terrain
        let candidates = ringCells(around: start, distance: townDistance, on: terrain)
            .filter { isTownSite($0, in: world) }
            .map { (cell: $0, score: flatness(around: $0, on: terrain)) }
            .sorted { ($0.score, tieBreak($0.cell)) > ($1.score, tieBreak($1.cell)) }

        var centres: [GridPoint] = []
        let offset = tieBreak(start)
        for candidate in candidates where centres.count < min(maximumTowns, catalog.townTemplates.count) {
            guard centres.allSatisfy({ distance($0, candidate.cell) >= 28 }) else { continue }
            let index = centres.count
            centres.append(candidate.cell)
            let template = catalog.townTemplates[(index + offset) % catalog.townTemplates.count]
            let name = townNames[(index + offset) % townNames.count]
            found(template, named: name, at: candidate.cell, stop: stop, in: &world)
        }
    }

    private static func found(_ template: TownTemplate, named name: String, at center: GridPoint, stop: BuildingDefinition, in world: inout WorldState) {
        // A crossroads through the centre.
        var roads: Set<GridPoint> = []
        for step in -townRadius...townRadius {
            roads.insert(center.offset(dx: step, dz: 0))
            roads.insert(center.offset(dx: 0, dz: step))
        }
        world.roads.formUnion(roads)

        let stopCell = center.offset(dx: 1, dz: 1)
        let stopID = world.addBuilding(stop, at: stopCell, resourceFactor: 1)
        let id = world.makeTownID()
        if let index = world.index(of: stopID) {
            world.buildings[index].townID = id
        }

        var footprint: Set<GridPoint> = []
        for dz in -townRadius...townRadius {
            for dx in -townRadius...townRadius {
                let cell = center.offset(dx: dx, dz: dz)
                if !roads.contains(cell) && cell != stopCell {
                    footprint.insert(cell)
                }
            }
        }
        world.towns.append(NeighbourTown(id: id, name: name, template: template, center: center, stopID: stopID, footprint: footprint))
    }

    private static func isTownSite(_ center: GridPoint, in world: WorldState) -> Bool {
        let terrain = world.terrain
        let reach = townRadius + 1
        for dz in -reach...reach {
            for dx in -reach...reach {
                let cell = center.offset(dx: dx, dz: dz)
                guard
                    terrain.contains(cell),
                    terrain.isLand(cell),
                    terrain.biome(at: cell) != .rock,
                    terrain.deposit(at: cell) == nil,
                    terrain.slopePercent(at: cell) <= 15,
                    !world.isOccupied(cell)
                else { return false }
            }
        }
        return true
    }

    private static func flatness(around center: GridPoint, on terrain: Terrain) -> Double {
        var worst = 0.0
        for dz in -townRadius...townRadius {
            for dx in -townRadius...townRadius {
                worst = max(worst, terrain.slopePercent(at: center.offset(dx: dx, dz: dz)))
            }
        }
        return -worst
    }

    // MARK: - Helpers

    private static func ringCells(around start: GridPoint, distance range: ClosedRange<Int>, on terrain: Terrain) -> [GridPoint] {
        var cells: [GridPoint] = []
        let outer = range.upperBound
        for dz in -outer...outer {
            for dx in -outer...outer {
                let d = Int(Double(dx * dx + dz * dz).squareRoot())
                let cell = start.offset(dx: dx, dz: dz)
                if range.contains(d) && terrain.contains(cell) {
                    cells.append(cell)
                }
            }
        }
        return cells
    }

    private static func isBuildable(_ cell: GridPoint, on terrain: Terrain) -> Bool {
        terrain.isLand(cell) && terrain.biome(at: cell) != .snow && terrain.slopePercent(at: cell) <= 30
    }

    private static func distance(_ a: GridPoint, _ b: GridPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dz = Double(a.z - b.z)
        return (dx * dx + dz * dz).squareRoot()
    }

    /// Stable pseudo-random number per cell, to break ties without a random generator.
    private static func tieBreak(_ cell: GridPoint) -> Int {
        var h = UInt64(truncatingIfNeeded: (cell.x &* 73_856_093) ^ (cell.z &* 19_349_663))
        h = (h ^ (h >> 13)) &* 0x5BD1_E995
        return Int(h % 65_521)
    }
}
