import GameDomain

/// Places what makes the region more than one village: deposits of stone and vines
/// away from the start, and neutral towns further out.
///
/// The first deposits and towns lie in a ring around the start, beyond carrier range,
/// so using them needs roads, stops and lines. Larger maps get more of both, spread
/// over the whole map. Placement is deterministic: the same terrain always yields the
/// same region.
enum RegionPlanner {
    /// Deposits lie this many cells from the start (carriers reach about 19 cells).
    static let depositDistance = 22...45
    /// Towns lie this many cells from the start.
    static let townDistance = 34...60
    /// Deposits of each kind in the ring around the start.
    static let clustersPerDeposit = 3
    /// Cells per map edge of the 1 km reference map; larger maps get proportionally more.
    static let referenceSize = 128
    /// Cells around a town's centre covered by its houses and roads.
    static let townRadius = 3
    /// Proper names for towns; they are not translated.
    static let townNames = ["Aquilon", "Belcastro", "Corvia", "Dunmere", "Esterra", "Falkenau", "Galena", "Hollin", "Isenhag", "Junara"]

    /// Towns per map: 3 on the reference map, up to 10 on an 8 km map.
    static func townCount(forMapSize size: Int) -> Int {
        min(townNames.count, max(3, 2 + size / referenceSize))
    }

    /// Extra deposit clusters of each kind spread over larger maps (none on the reference map).
    static func extraClusters(forMapSize size: Int) -> Int {
        let area = Double(size * size) / Double(referenceSize * referenceSize)
        return Int((area - 1) * 0.75)
    }

    /// Minimum distance between towns in cells.
    static func townSpacing(forMapSize size: Int) -> Double {
        max(28, Double(size) / 12)
    }

    // MARK: - Deposits

    static func addDeposits(to terrain: Terrain, around start: GridPoint) -> Terrain {
        var placed: [GridPoint: Deposit] = [:]
        var centres: [GridPoint] = []
        func place(_ deposit: Deposit, count: Int, among cells: [GridPoint], spacing: Double) {
            let candidates = cells
                .filter { isBuildable($0, on: terrain) }
                .map { (cell: $0, score: score(of: $0, for: deposit, on: terrain)) }
                .sorted { ($0.score, tieBreak($0.cell)) > ($1.score, tieBreak($1.cell)) }
            var chosen = 0
            for candidate in candidates where chosen < count {
                // Keep clusters apart so they spread over the map.
                guard centres.allSatisfy({ distance($0, candidate.cell) >= spacing }) else { continue }
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

        // First a few near the start, then more across larger maps.
        for deposit in Deposit.allCases {
            place(deposit, count: clustersPerDeposit, among: ringCells(around: start, distance: depositDistance, on: terrain), spacing: 16)
        }
        let extra = extraClusters(forMapSize: terrain.size)
        if extra > 0 {
            let far = sampledCells(on: terrain, stride: 3).filter { distance($0, start) > Double(depositDistance.upperBound) }
            for deposit in Deposit.allCases {
                place(deposit, count: extra, among: far, spacing: 24)
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
        // Near towns lie in the ring around the start; on larger maps the rest spread across it.
        let reach = max(townDistance.upperBound, terrain.size)
        let area = terrain.size > referenceSize * 2
            ? sampledCells(on: terrain, stride: 2).filter { distance($0, start) >= Double(townDistance.lowerBound) }
            : ringCells(around: start, distance: townDistance.lowerBound...reach, on: terrain)
        let candidates = area
            .filter { isTownSite($0, in: world) }
            .map { (cell: $0, score: flatness(around: $0, on: terrain)) }
            .sorted { ($0.score, tieBreak($0.cell)) > ($1.score, tieBreak($1.cell)) }

        var centres: [GridPoint] = []
        let offset = tieBreak(start)
        let count = townCount(forMapSize: terrain.size)
        let spacing = townSpacing(forMapSize: terrain.size)
        // The nearest town is placed first, so every map has a trading partner within reach.
        if let near = candidates.first(where: { townDistance.contains(Int(distance($0.cell, start))) }) {
            centres.append(near.cell)
            found(catalog.townTemplates[offset % catalog.townTemplates.count], named: townNames[offset % townNames.count], at: near.cell, stop: stop, in: &world)
        }
        for candidate in candidates where centres.count < count {
            guard centres.allSatisfy({ distance($0, candidate.cell) >= spacing }) else { continue }
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

    /// Every `stride`-th cell in both directions, for searches over the whole map.
    private static func sampledCells(on terrain: Terrain, stride step: Int) -> [GridPoint] {
        var cells: [GridPoint] = []
        for z in stride(from: 0, to: terrain.size, by: step) {
            for x in stride(from: 0, to: terrain.size, by: step) {
                cells.append(GridPoint(x: x, z: z))
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
