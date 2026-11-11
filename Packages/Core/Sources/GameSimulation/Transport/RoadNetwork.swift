import GameDomain

/// Pathfinding on the road network.
///
/// Routes are searched on the ``RoadGraph``: from every road cell next to the origin
/// building to any road cell next to the destination building. Tunnels are ordinary
/// road cells for routing.
public enum RoadNetwork {
    /// Road cells next to a cell (4-neighbourhood).
    public static func access(to cell: GridPoint, roads: Set<GridPoint>) -> [GridPoint] {
        [cell.offset(dx: 1, dz: 0), cell.offset(dx: -1, dz: 0), cell.offset(dx: 0, dz: 1), cell.offset(dx: 0, dz: -1)]
            .filter(roads.contains)
    }

    /// Shortest road path between two buildings' cells, as road cells in driving order,
    /// or `nil` if they are not connected. Builds a graph for the given roads; use the
    /// overload with a world to reuse its graph.
    public static func path(from origin: GridPoint, to destination: GridPoint, roads: Set<GridPoint>) -> [GridPoint]? {
        path(from: origin, to: destination, roads: roads, graph: RoadGraph(roads: roads))
    }

    static func path(from origin: GridPoint, to destination: GridPoint, roads: Set<GridPoint>, graph: RoadGraph) -> [GridPoint]? {
        let starts = access(to: origin, roads: roads)
        let goals = Set(access(to: destination, roads: roads))
        guard !starts.isEmpty, !goals.isEmpty else { return nil }
        return graph.path(from: starts, to: goals)
    }

    /// Driving waypoints from one building to another: its centre, the road cells, the other centre.
    public static func route(from origin: Building, to destination: Building, in world: WorldState) -> [WorldPoint]? {
        guard let cells = path(from: origin.cell, to: destination.cell, roads: world.roads, graph: world.roadGraph) else { return nil }
        return [origin.center] + cells.map(world.terrain.center(of:)) + [destination.center]
    }
}
