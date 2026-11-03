import GameDomain

/// Rules for road cells and helpers to plan road paths.
public enum RoadPlanner {
    /// Whether a road may be built on a cell (ignoring cost).
    public static func validate(_ cell: GridPoint, in world: WorldState) -> Result<Void, PlacementError> {
        let terrain = world.terrain
        guard terrain.contains(cell) else { return .failure(.outOfBounds) }
        guard terrain.isLand(cell) else { return .failure(.water) }
        let slope = terrain.slopePercent(at: cell)
        guard slope <= world.rules.maxRoadSlopePercent else { return .failure(.tooSteep(slopePercent: slope)) }
        guard !world.isOccupied(cell) else { return .failure(.occupied) }
        return .success(())
    }

    /// An L-shaped path from `start` to `end`: first along the longer axis, then the shorter one.
    /// Both ends are included; consecutive cells are edge neighbours.
    public static func path(from start: GridPoint, to end: GridPoint) -> [GridPoint] {
        let dx = end.x - start.x
        let dz = end.z - start.z
        var cells = [start]
        var current = start
        func walk(alongX: Bool, steps: Int) {
            let step = steps > 0 ? 1 : -1
            for _ in 0..<abs(steps) {
                current = alongX ? current.offset(dx: step, dz: 0) : current.offset(dx: 0, dz: step)
                cells.append(current)
            }
        }
        if abs(dx) >= abs(dz) {
            walk(alongX: true, steps: dx)
            walk(alongX: false, steps: dz)
        } else {
            walk(alongX: false, steps: dz)
            walk(alongX: true, steps: dx)
        }
        return cells
    }

    /// The cells of `cells` that would actually be built: new, valid, in order, without duplicates.
    public static func buildableCells(_ cells: [GridPoint], in world: WorldState) -> [GridPoint] {
        var seen = Set<GridPoint>()
        return cells.filter { cell in
            guard seen.insert(cell).inserted, !world.hasRoad(at: cell) else { return false }
            if case .success = validate(cell, in: world) { return true }
            return false
        }
    }
}

/// Builds gravel road on the given cells. Invalid cells and cells that already have a road
/// are skipped; the whole command is rejected if the valid cells cannot be paid for.
public struct BuildRoadCommand: GameCommand {
    public let cells: [GridPoint]

    public init(cells: [GridPoint]) {
        self.cells = cells
    }

    public func execute(in world: inout WorldState) {
        let buildable = RoadPlanner.buildableCells(cells, in: world)
        guard !buildable.isEmpty else {
            if let error = firstError(in: world) {
                world.emit(.placementRejected(error))
            }
            return
        }
        let cost = buildable.count * world.rules.roadCostPerCell
        guard world.treasury >= cost else {
            world.emit(.placementRejected(.insufficientFunds(cost: cost)))
            return
        }
        world.treasury -= cost
        world.roads.formUnion(buildable)
        world.emit(.roadBuilt(cells: buildable.count, cost: cost))
    }

    private func firstError(in world: WorldState) -> PlacementError? {
        for cell in cells where !world.hasRoad(at: cell) {
            if case .failure(let error) = RoadPlanner.validate(cell, in: world) {
                return error
            }
        }
        return nil
    }
}

/// Removes road from the given cells and refunds part of the cost.
public struct DemolishRoadCommand: GameCommand {
    public let cells: [GridPoint]

    public init(cells: [GridPoint]) {
        self.cells = cells
    }

    public func execute(in world: inout WorldState) {
        let removed = Set(cells).intersection(world.roads)
        guard !removed.isEmpty else { return }
        world.roads.subtract(removed)
        let refund = removed.count * world.rules.roadCostPerCell * world.rules.demolitionRefundPercent / 100
        world.treasury += refund
        world.emit(.roadDemolished(cells: removed.count, refund: refund))
    }
}
