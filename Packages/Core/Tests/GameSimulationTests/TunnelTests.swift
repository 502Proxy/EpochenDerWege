import GameDomain
@testable import GameSimulation
import Testing

@Suite("Road tunnels")
struct TunnelTests {
    /// 16 × 16 flat map with a steep ridge between x = 6 and x = 9 (corner heights rise 8 m per cell).
    private func ridgeSimulation() throws -> Simulation {
        let size = 16
        var heights = [Double](repeating: 10, count: (size + 1) * (size + 1))
        for z in 0...size {
            for x in 0...size {
                let rise: Double = switch x {
                case 7: 18
                case 8: 26
                case 9: 18
                default: 10
                }
                heights[z * (size + 1) + x] = rise
            }
        }
        let terrain = Terrain(size: size, cellSize: 8, seaLevel: 0, heights: heights, biomes: Array(repeating: .grass, count: size * size))
        let world = WorldFactory.makeWorld(catalog: try Fixtures.catalog(), terrain: terrain, foundSettlement: false)
        return Simulation(world: world)
    }

    @Test func steepCellsBecomeTunnels() throws {
        var simulation = try ridgeSimulation()
        let path = RoadPlanner.path(from: GridPoint(x: 2, z: 4), to: GridPoint(x: 12, z: 4))
        let plan = RoadPlanner.plan(path, in: simulation.world)
        let tunnels = Set(plan.filter { $0.kind == .tunnel }.map(\.cell))
        #expect(tunnels == [GridPoint(x: 6, z: 4), GridPoint(x: 7, z: 4), GridPoint(x: 8, z: 4), GridPoint(x: 9, z: 4)])

        simulation.execute(BuildRoadCommand(cells: path))
        let rules = simulation.world.rules
        #expect(simulation.world.roads.count == 11)
        #expect(simulation.world.tunnels == tunnels)
        #expect(simulation.lastEvent == .roadBuilt(cells: 11, cost: 7 * rules.roadCostPerCell + 4 * rules.tunnelCostPerCell))
    }

    @Test func demolishingATunnelRefundsHalfOfItsCost() throws {
        var simulation = try ridgeSimulation()
        simulation.execute(BuildRoadCommand(cells: RoadPlanner.path(from: GridPoint(x: 2, z: 4), to: GridPoint(x: 12, z: 4))))
        let before = simulation.world.treasury
        simulation.execute(DemolishRoadCommand(cells: [GridPoint(x: 7, z: 4)]))
        #expect(simulation.world.treasury == before + simulation.world.rules.tunnelCostPerCell / 2)
        #expect(!simulation.world.tunnels.contains(GridPoint(x: 7, z: 4)))
    }

    @Test func flatGroundNeedsNoTunnel() throws {
        var simulation = try Fixtures.flatSimulation(settlement: false)
        simulation.execute(BuildRoadCommand(cells: RoadPlanner.path(from: GridPoint(x: 0, z: 0), to: GridPoint(x: 6, z: 0))))
        #expect(simulation.world.tunnels.isEmpty)
    }
}
