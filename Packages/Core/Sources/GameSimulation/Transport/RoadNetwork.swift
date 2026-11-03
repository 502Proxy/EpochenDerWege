import GameDomain

/// Pathfinding on the road network (A*).
///
/// Road cells are nodes; edge neighbours are connected. Tunnels are ordinary road
/// cells for routing. The search starts from every road cell next to the origin
/// building and ends at any road cell next to the destination building.
public enum RoadNetwork {
    /// Road cells next to a cell (4-neighbourhood).
    public static func access(to cell: GridPoint, roads: Set<GridPoint>) -> [GridPoint] {
        [cell.offset(dx: 1, dz: 0), cell.offset(dx: -1, dz: 0), cell.offset(dx: 0, dz: 1), cell.offset(dx: 0, dz: -1)]
            .filter(roads.contains)
    }

    /// Shortest road path between two buildings' cells, as road cells in driving order,
    /// or `nil` if they are not connected.
    public static func path(from origin: GridPoint, to destination: GridPoint, roads: Set<GridPoint>) -> [GridPoint]? {
        let starts = access(to: origin, roads: roads)
        let goals = Set(access(to: destination, roads: roads))
        guard !starts.isEmpty, !goals.isEmpty else { return nil }

        func heuristic(_ cell: GridPoint) -> Int {
            max(0, abs(cell.x - destination.x) + abs(cell.z - destination.z) - 1)
        }

        var open = MinHeap()
        var cost: [GridPoint: Int] = [:]
        var cameFrom: [GridPoint: GridPoint] = [:]
        for start in starts {
            cost[start] = 0
            open.push(start, priority: heuristic(start))
        }

        while let current = open.pop() {
            if goals.contains(current) {
                var path = [current]
                var node = current
                while let previous = cameFrom[node] {
                    path.append(previous)
                    node = previous
                }
                return path.reversed()
            }
            let currentCost = cost[current, default: .max]
            for next in access(to: current, roads: roads) {
                let newCost = currentCost + 1
                if newCost < cost[next, default: .max] {
                    cost[next] = newCost
                    cameFrom[next] = current
                    open.push(next, priority: newCost + heuristic(next))
                }
            }
        }
        return nil
    }

    /// Driving waypoints from one building to another: its centre, the road cells, the other centre.
    public static func route(from origin: Building, to destination: Building, in world: WorldState) -> [WorldPoint]? {
        guard let cells = path(from: origin.cell, to: destination.cell, roads: world.roads) else { return nil }
        return [origin.center] + cells.map(world.terrain.center(of:)) + [destination.center]
    }
}

/// Binary min-heap keyed by an integer priority; ties are broken by position for determinism.
private struct MinHeap {
    private var items: [(priority: Int, cell: GridPoint)] = []

    mutating func push(_ cell: GridPoint, priority: Int) {
        items.append((priority, cell))
        var child = items.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard Self.less(items[child], items[parent]) else { break }
            items.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> GridPoint? {
        guard !items.isEmpty else { return nil }
        items.swapAt(0, items.count - 1)
        let top = items.removeLast()
        var parent = 0
        while true {
            let left = parent * 2 + 1
            let right = left + 1
            var smallest = parent
            if left < items.count && Self.less(items[left], items[smallest]) { smallest = left }
            if right < items.count && Self.less(items[right], items[smallest]) { smallest = right }
            guard smallest != parent else { break }
            items.swapAt(parent, smallest)
            parent = smallest
        }
        return top.cell
    }

    private static func less(_ a: (priority: Int, cell: GridPoint), _ b: (priority: Int, cell: GridPoint)) -> Bool {
        (a.priority, a.cell.z, a.cell.x) < (b.priority, b.cell.z, b.cell.x)
    }
}
