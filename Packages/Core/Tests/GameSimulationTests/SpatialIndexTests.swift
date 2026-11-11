import Foundation
import GameDomain
@testable import GameSimulation
import Testing

@Suite("Spatial index")
struct SpatialIndexTests {
    /// The same answer as checking every building, in the same order.
    private func bruteForce(_ world: WorldState, within radius: Double, of point: WorldPoint) -> [BuildingID] {
        world.buildings.filter { $0.center.distance(to: point) <= radius }.map(\.id)
    }

    /// A 64 × 64 map with storehouses on a scattered pattern.
    private func crowdedWorld() throws -> WorldState {
        var simulation = try Fixtures.flatSimulation(size: 64, settlement: false) { $0.startingTreasury = 1_000_000 }
        for z in stride(from: 1, to: 64, by: 3) {
            for x in stride(from: (z * 7) % 5, to: 64, by: 4) {
                simulation.execute(PlaceBuildingCommand(buildingType: "storehouse", cell: GridPoint(x: x, z: z)))
            }
        }
        return simulation.world
    }

    @Test func rangeQueriesMatchCheckingEveryBuilding() throws {
        let world = try crowdedWorld()
        #expect(world.buildings.count > 200)
        for point in [WorldPoint(x: 0, z: 0), WorldPoint(x: 260, z: 260), WorldPoint(x: 511, z: 30), WorldPoint(x: 100.5, z: 400.25)] {
            for radius in [10.0, 64, 150, 400] {
                #expect(world.buildings(within: radius, of: point).map(\.id) == bruteForce(world, within: radius, of: point))
            }
        }
    }

    @Test func indexFollowsDemolitions() throws {
        var simulation = Simulation(world: try crowdedWorld())
        let removed = simulation.world.buildings.enumerated().filter { $0.offset % 3 == 0 }.map(\.element.id)
        for id in removed {
            simulation.execute(DemolishBuildingCommand(buildingID: id))
        }
        let world = simulation.world
        let point = WorldPoint(x: 256, z: 256)
        #expect(world.buildings(within: 200, of: point).map(\.id) == bruteForce(world, within: 200, of: point))
        #expect(world.buildings(within: 10_000, of: point).allSatisfy { !removed.contains($0.id) })
    }

    @Test func indexIsRebuiltWhenAWorldIsDecoded() throws {
        let world = try crowdedWorld()
        let restored = try JSONDecoder().decode(WorldState.self, from: JSONEncoder().encode(world))
        let point = WorldPoint(x: 300, z: 120)
        #expect(restored.buildings(within: 150, of: point).map(\.id) == bruteForce(world, within: 150, of: point))
    }
}
