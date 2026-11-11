import GameDomain

/// The road network as a graph: junctions and dead ends are nodes, the stretches of
/// road between them are edges.
///
/// Routing on the graph visits only junctions instead of every road cell, which
/// matters on a large map with long roads. It is the basis for road types, traffic
/// and pedestrians. The graph is rebuilt from the road cells whenever they change;
/// that happens only when the player builds or demolishes roads.
public struct RoadGraph: Sendable {
    /// A stretch of road between two nodes, including both of them.
    public struct Edge: Hashable, Sendable {
        public let cells: [GridPoint]
        public var from: GridPoint { cells[0] }
        public var to: GridPoint { cells[cells.count - 1] }
        /// Length in cells.
        public var length: Int { cells.count - 1 }
    }

    /// Junctions (three or more neighbours), dead ends, single cells, and one cell of every closed loop.
    public private(set) var nodes: Set<GridPoint> = []
    public private(set) var edges: [Edge] = []
    private var edgesAtNode: [GridPoint: [Int]] = [:]
    /// For cells inside an edge: the edge and the cell's position in it.
    private var placeOfCell: [GridPoint: (edge: Int, index: Int)] = [:]

    public init() {}

    public init(roads: Set<GridPoint>) {
        func neighbours(_ cell: GridPoint) -> [GridPoint] {
            [cell.offset(dx: 1, dz: 0), cell.offset(dx: -1, dz: 0), cell.offset(dx: 0, dz: 1), cell.offset(dx: 0, dz: -1)]
                .filter(roads.contains)
        }
        let ordered = roads.sorted { ($0.z, $0.x) < ($1.z, $1.x) }
        nodes = Set(ordered.filter { neighbours($0).count != 2 })

        var visited = Set<GridPoint>()
        // Walk from every node along each of its roads to the next node.
        for node in ordered where nodes.contains(node) {
            for first in neighbours(node) {
                trace(from: node, via: first, neighbours: neighbours, visited: &visited)
            }
        }
        // Closed loops without any junction: make their first cell a node.
        for cell in ordered where !nodes.contains(cell) && !visited.contains(cell) {
            nodes.insert(cell)
            for first in neighbours(cell) {
                trace(from: cell, via: first, neighbours: neighbours, visited: &visited)
            }
        }
    }

    private mutating func trace(from start: GridPoint, via first: GridPoint, neighbours: (GridPoint) -> [GridPoint], visited: inout Set<GridPoint>) {
        // Each edge is traced once, from the end that comes first.
        if !nodes.contains(first) && visited.contains(first) { return }
        var cells = [start, first]
        var previous = start
        var current = first
        while !nodes.contains(current) {
            visited.insert(current)
            guard let next = neighbours(current).first(where: { $0 != previous }) else { break }
            previous = current
            current = next
            cells.append(current)
        }
        if nodes.contains(current) && cells.count == 2 {
            // Two neighbouring nodes: one edge, traced from the earlier node only.
            guard (start.z, start.x) < (current.z, current.x) else { return }
        }
        let index = edges.count
        edges.append(Edge(cells: cells))
        edgesAtNode[start, default: []].append(index)
        if current != start {
            edgesAtNode[current, default: []].append(index)
        }
        for (position, cell) in cells.enumerated().dropFirst().dropLast() {
            placeOfCell[cell] = (index, position)
        }
    }

    // MARK: - Routing

    /// Shortest path from any of `starts` to any of `goals`, as road cells in driving
    /// order including both ends, or `nil` if they are not connected.
    public func path(from starts: [GridPoint], to goals: Set<GridPoint>) -> [GridPoint]? {
        let starts = starts.filter { nodes.contains($0) || placeOfCell[$0] != nil }
        guard !starts.isEmpty, !goals.isEmpty else { return nil }

        // A start and a goal on the same stretch of road: drive along it directly.
        var best: (cost: Int, cells: [GridPoint])?
        for start in starts {
            for goal in goals.sorted(by: { ($0.z, $0.x) < ($1.z, $1.x) }) {
                if let direct = directPath(from: start, to: goal), best.map({ direct.count - 1 < $0.cost }) ?? true {
                    best = (direct.count - 1, direct)
                }
            }
        }

        // Dijkstra over nodes. Entry: from each start to the nodes at the ends of its edge.
        var distance: [GridPoint: Int] = [:]
        var cameFrom: [GridPoint: Step] = [:]
        var open = MinHeap()
        for start in starts {
            for (node, cells) in exits(from: start) where cells.count - 1 < distance[node, default: .max] {
                distance[node] = cells.count - 1
                cameFrom[node] = Step(previous: start, cells: cells, isStart: true)
                open.push(node, priority: cells.count - 1)
            }
        }

        while let entry = open.pop() {
            let node = entry.cell
            let cost = entry.priority
            // Skip outdated heap entries, and stop once nothing can beat the best path found.
            guard cost == distance[node], cost < best?.cost ?? .max else { continue }
            for (_, cells) in arrivals(from: node, at: goals) where cost + cells.count - 1 < best?.cost ?? .max {
                best = (cost + cells.count - 1, unwind(to: node, in: cameFrom) + cells.dropFirst())
            }
            for edgeIndex in edgesAtNode[node, default: []] {
                let edge = edges[edgeIndex]
                let next = edge.from == node ? edge.to : edge.from
                let cells = edge.from == node ? edge.cells : Array(edge.cells.reversed())
                let newCost = cost + edge.length
                if newCost < distance[next, default: .max] {
                    distance[next] = newCost
                    cameFrom[next] = Step(previous: node, cells: cells, isStart: false)
                    open.push(next, priority: newCost)
                }
            }
        }
        return best?.cells
    }

    /// How the search reached a node: the cells driven from the previous node or start.
    private struct Step {
        let previous: GridPoint
        let cells: [GridPoint]
        let isStart: Bool
    }

    /// Cells from the start to `node`, following the recorded steps backwards.
    private func unwind(to node: GridPoint, in cameFrom: [GridPoint: Step]) -> [GridPoint] {
        var pieces: [[GridPoint]] = []
        var current = node
        while let step = cameFrom[current] {
            pieces.append(step.cells)
            if step.isStart { break }
            current = step.previous
        }
        var path: [GridPoint] = []
        for piece in pieces.reversed() {
            path.append(contentsOf: path.isEmpty ? piece : Array(piece.dropFirst()))
        }
        return path
    }

    /// Cells from a start cell to the nodes at both ends of its edge (or just the node itself).
    private func exits(from cell: GridPoint) -> [(GridPoint, [GridPoint])] {
        if nodes.contains(cell) {
            return [(cell, [cell])]
        }
        guard let place = placeOfCell[cell] else { return [] }
        let cells = edges[place.edge].cells
        return [
            (cells[0], Array(cells[...place.index].reversed())),
            (cells[cells.count - 1], Array(cells[place.index...])),
        ]
    }

    /// Goals reachable from a node without passing another node, with the cells from the node to the goal.
    private func arrivals(from node: GridPoint, at goals: Set<GridPoint>) -> [(GridPoint, [GridPoint])] {
        var result: [(GridPoint, [GridPoint])] = []
        if goals.contains(node) {
            result.append((node, [node]))
        }
        for edgeIndex in edgesAtNode[node, default: []] {
            let edge = edges[edgeIndex]
            // A loop that starts and ends at this node can be driven both ways round.
            var directions: [[GridPoint]] = []
            if edge.from == node { directions.append(edge.cells) }
            if edge.to == node { directions.append(edge.cells.reversed()) }
            for cells in directions {
                for (position, cell) in cells.enumerated().dropFirst().dropLast() where goals.contains(cell) {
                    result.append((cell, Array(cells[...position])))
                }
            }
        }
        return result
    }

    /// Path between two cells of the same edge without passing a node.
    private func directPath(from start: GridPoint, to goal: GridPoint) -> [GridPoint]? {
        if start == goal {
            return [start]
        }
        guard let a = placeOfCell[start], let b = placeOfCell[goal], a.edge == b.edge else { return nil }
        let cells = edges[a.edge].cells
        return a.index <= b.index ? Array(cells[a.index...b.index]) : Array(cells[b.index...a.index].reversed())
    }
}

/// Binary min-heap keyed by an integer priority; ties are broken by position for determinism.
struct MinHeap {
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

    mutating func pop() -> (cell: GridPoint, priority: Int)? {
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
        return (top.cell, top.priority)
    }

    private static func less(_ a: (priority: Int, cell: GridPoint), _ b: (priority: Int, cell: GridPoint)) -> Bool {
        (a.priority, a.cell.z, a.cell.x) < (b.priority, b.cell.z, b.cell.x)
    }
}
