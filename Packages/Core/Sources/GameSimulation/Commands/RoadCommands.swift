import GameDomain

/// How a road cell is built.
public enum RoadKind: Hashable, Sendable {
    /// On the surface.
    case surface
    /// Through the hill, for cells too steep for a surface road.
    case tunnel
}

/// Rules for road cells and helpers to plan road paths.
public enum RoadPlanner {
    /// Whether and how a road may be built on a cell (ignoring cost).
    /// Cells steeper than `maxRoadSlopePercent` become tunnels; water blocks roads.
    public static func validate(_ cell: GridPoint, in world: WorldState) -> Result<RoadKind, PlacementError> {
        let terrain = world.terrain
        guard terrain.contains(cell) else { return .failure(.outOfBounds) }
        guard terrain.isLand(cell) else { return .failure(.water) }
        guard !world.isOccupied(cell) else { return .failure(.occupied) }
        return .success(terrain.slopePercent(at: cell) > world.rules.maxRoadSlopePercent ? .tunnel : .surface)
    }

    /// Cost of building one cell of the given kind.
    public static func cost(of kind: RoadKind, rules: GameRules) -> Int {
        switch kind {
        case .surface: rules.roadCostPerCell
        case .tunnel: rules.tunnelCostPerCell
        }
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

    /// The cells of `cells` that would actually be built, with their kind: new, valid,
    /// in order, without duplicates.
    public static func plan(_ cells: [GridPoint], in world: WorldState) -> [(cell: GridPoint, kind: RoadKind)] {
        var seen = Set<GridPoint>()
        var result: [(cell: GridPoint, kind: RoadKind)] = []
        for cell in cells where seen.insert(cell).inserted && !world.hasRoad(at: cell) {
            if case .success(let kind) = validate(cell, in: world) {
                result.append((cell, kind))
            }
        }
        return result
    }

    /// The cells of `cells` that would actually be built.
    public static func buildableCells(_ cells: [GridPoint], in world: WorldState) -> [GridPoint] {
        plan(cells, in: world).map(\.cell)
    }
}

/// Builds gravel road on the given cells; cells too steep for a surface road become tunnels. Invalid cells and cells that already have a road
/// are skipped; the whole command is rejected if the valid cells cannot be paid for.
public struct BuildRoadCommand: GameCommand {
    public let cells: [GridPoint]

    public init(cells: [GridPoint]) {
        self.cells = cells
    }

    public func execute(in world: inout WorldState) {
        let buildable = RoadPlanner.plan(cells, in: world)
        guard !buildable.isEmpty else {
            if let error = firstError(in: world) {
                world.emit(.placementRejected(error))
            }
            return
        }
        let rules = world.rules
        let cost = buildable.reduce(0) { $0 + RoadPlanner.cost(of: $1.kind, rules: rules) }
        guard world.treasury >= cost else {
            world.emit(.placementRejected(.insufficientFunds(cost: cost)))
            return
        }
        world.book(-cost, as: .roads)
        // One change each, so the road graph is rebuilt once.
        world.roads.formUnion(buildable.map(\.cell))
        world.tunnels.formUnion(buildable.filter { $0.kind == .tunnel }.map(\.cell))
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
        let rules = world.rules
        let value = removed.reduce(0) { total, cell in
            total + RoadPlanner.cost(of: world.tunnels.contains(cell) ? .tunnel : .surface, rules: rules)
        }
        world.roads.subtract(removed)
        world.tunnels.subtract(removed)
        let refund = value * rules.demolitionRefundPercent / 100
        world.book(refund, as: .refunds)
        world.emit(.roadDemolished(cells: removed.count, refund: refund))
    }
}
