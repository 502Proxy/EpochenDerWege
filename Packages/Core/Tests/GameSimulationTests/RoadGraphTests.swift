import GameDomain
@testable import GameSimulation
import Testing

@Suite("Road graph")
struct RoadGraphTests {
    private func cells(_ points: [(Int, Int)]) -> Set<GridPoint> {
        Set(points.map { GridPoint(x: $0.0, z: $0.1) })
    }

    /// Breadth-first search on cells: the reference for shortest path lengths.
    private func referenceLength(from starts: [GridPoint], to goals: Set<GridPoint>, roads: Set<GridPoint>) -> Int? {
        var distance: [GridPoint: Int] = [:]
        var queue: [GridPoint] = []
        for start in starts {
            distance[start] = 0
            queue.append(start)
        }
        var head = 0
        while head < queue.count {
            let cell = queue[head]
            head += 1
            if goals.contains(cell) {
                return distance[cell]
            }
            for next in RoadNetwork.access(to: cell, roads: roads) where distance[next] == nil {
                distance[next] = distance[cell, default: 0] + 1
                queue.append(next)
            }
        }
        return nil
    }

    private func isValid(_ path: [GridPoint], roads: Set<GridPoint>) -> Bool {
        path.allSatisfy(roads.contains)
            && zip(path, path.dropFirst()).allSatisfy { abs($0.x - $1.x) + abs($0.z - $1.z) == 1 }
    }

    @Test func straightRoadIsOneEdge() {
        let graph = RoadGraph(roads: cells((0...9).map { ($0, 0) }))
        #expect(graph.nodes == cells([(0, 0), (9, 0)]))
        #expect(graph.edges.count == 1)
        #expect(graph.edges.first?.length == 9)
    }

    @Test func junctionSplitsRoads() {
        // A T: a road along x and a branch going up from the middle.
        let roads = cells((0...8).map { ($0, 0) } + (1...4).map { (4, $0) })
        let graph = RoadGraph(roads: roads)
        #expect(graph.nodes == cells([(0, 0), (8, 0), (4, 0), (4, 4)]))
        #expect(graph.edges.count == 3)
        #expect(graph.edges.map(\.length).sorted() == [4, 4, 4])
    }

    @Test func loopWithoutJunctionsIsRoutable() {
        var ring: [(Int, Int)] = []
        for x in 0...4 { ring += [(x, 0), (x, 4)] }
        for z in 1...3 { ring += [(0, z), (4, z)] }
        let roads = cells(ring)
        let graph = RoadGraph(roads: roads)
        #expect(graph.nodes.count == 1)
        let path = try? #require(graph.path(from: [GridPoint(x: 1, z: 0)], to: [GridPoint(x: 3, z: 4)]))
        #expect(path.map { isValid($0, roads: roads) } == true)
        #expect(path.map { $0.count - 1 } == 8)
    }

    @Test func neighbouringJunctionsAndSingleCells() {
        // A plus sign: centre and four arms of length one, all nodes.
        let roads = cells([(5, 5), (4, 5), (6, 5), (5, 4), (5, 6), (9, 9)])
        let graph = RoadGraph(roads: roads)
        #expect(graph.edges.count == 4)
        #expect(graph.path(from: [GridPoint(x: 4, z: 5)], to: [GridPoint(x: 6, z: 5)])?.count == 3)
        #expect(graph.path(from: [GridPoint(x: 4, z: 5)], to: [GridPoint(x: 9, z: 9)]) == nil)
    }

    @Test(arguments: [UInt64(1), 2, 3, 4, 5])
    func pathsAreAsShortAsSearchingEveryCell(seed: UInt64) {
        // A random grid of streets with gaps.
        var random = SplitMix64(seed: seed)
        var roads = Set<GridPoint>()
        for line in stride(from: 0, to: 40, by: 5) {
            for step in 0..<40 where random.next() % 10 != 0 {
                roads.insert(GridPoint(x: step, z: line))
                roads.insert(GridPoint(x: line, z: step))
            }
        }
        let graph = RoadGraph(roads: roads)
        let ordered = roads.sorted { ($0.z, $0.x) < ($1.z, $1.x) }
        for _ in 0..<40 {
            let start = ordered[Int(random.next() % UInt64(ordered.count))]
            let goal = ordered[Int(random.next() % UInt64(ordered.count))]
            let path = graph.path(from: [start], to: [goal])
            let expected = referenceLength(from: [start], to: [goal], roads: roads)
            #expect(path.map { $0.count - 1 } == expected)
            if let path {
                #expect(path.first == start && path.last == goal)
                #expect(isValid(path, roads: roads))
            }
        }
    }

    @Test func worldKeepsItsGraphInSync() throws {
        var simulation = try Fixtures.flatSimulation(settlement: false)
        simulation.execute(BuildRoadCommand(cells: RoadPlanner.path(from: GridPoint(x: 2, z: 2), to: GridPoint(x: 10, z: 2))))
        #expect(simulation.world.roadGraph.edges.count == 1)
        simulation.execute(DemolishRoadCommand(cells: [GridPoint(x: 6, z: 2)]))
        #expect(simulation.world.roadGraph.edges.count == 2)
        #expect(simulation.world.roadGraph.path(from: [GridPoint(x: 2, z: 2)], to: [GridPoint(x: 10, z: 2)]) == nil)
    }
}
