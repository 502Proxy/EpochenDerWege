import GameDomain
@testable import GameSimulation
import Testing

@Suite("Processing buildings in zones")
struct ZonedProcessingTests {
    @Test func millOutsideAZoneIsRejected() throws {
        var simulation = try Fixtures.flatSimulation(settlement: false)
        simulation.execute(PlaceBuildingCommand(buildingType: "mill", cell: GridPoint(x: 4, z: 4)))
        #expect(simulation.lastEvent == .placementRejected(.requiresZone([.commercial, .industrial])))
        #expect(simulation.world.buildings.isEmpty)
    }

    @Test func millInResidentialZoneIsRejected() throws {
        var simulation = try Fixtures.flatSimulation(settlement: false)
        simulation.execute(ZoneCommand(cells: [GridPoint(x: 4, z: 4)], kind: .residential))
        simulation.execute(PlaceBuildingCommand(buildingType: "mill", cell: GridPoint(x: 4, z: 4)))
        #expect(simulation.lastEvent == .placementRejected(.requiresZone([.commercial, .industrial])))
    }

    @Test(arguments: [ZoneKind.commercial, .industrial])
    func bakeryInCommercialOrIndustrialZone(zone: ZoneKind) throws {
        var simulation = try Fixtures.flatSimulation(settlement: false)
        simulation.execute(ZoneCommand(cells: [GridPoint(x: 4, z: 4)], kind: zone))
        try simulation.place("bakery", x: 4, z: 4)
    }

    @Test func rawMaterialProducersNeedNoZone() throws {
        var simulation = try Fixtures.flatSimulation(settlement: false)
        try simulation.place("grainFarm", x: 4, z: 4)
    }
}
