import GameDomain

/// A player action (command pattern).
///
/// Commands are created on the main thread, queued, and executed by the simulation
/// between two ticks. This keeps all mutation in one place and makes actions easy to
/// log, replay or send over a network later.
public protocol GameCommand: Sendable {
    func execute(in world: inout WorldState)
}

/// Places a new building and pays for it.
public struct PlaceBuildingCommand: GameCommand {
    public let buildingType: BuildingTypeID
    public let cell: GridPoint

    public init(buildingType: BuildingTypeID, cell: GridPoint) {
        self.buildingType = buildingType
        self.cell = cell
    }

    public func execute(in world: inout WorldState) {
        guard let definition = world.catalog.building(buildingType) else {
            world.emit(.placementRejected(.unknownBuildingType(buildingType)))
            return
        }
        switch PlacementValidator.validate(definition, at: cell, in: world) {
        case .failure(let error):
            world.emit(.placementRejected(error))
        case .success(let resourceFactor):
            world.book(-definition.cost, as: .construction, detail: .building(definition.id))
            world.addBuilding(definition, at: cell, resourceFactor: resourceFactor)
            WorkforceSystem.assignWorkers(in: &world)
            world.emit(.buildingPlaced(buildingType, cost: definition.cost))
        }
    }
}

/// Demolishes a building and refunds part of its cost. Stock inside is lost.
public struct DemolishBuildingCommand: GameCommand {
    public let buildingID: BuildingID

    public init(buildingID: BuildingID) {
        self.buildingID = buildingID
    }

    public func execute(in world: inout WorldState) {
        // Towns keep their stops.
        guard world.building(buildingID)?.townID == nil, let removed = world.removeBuilding(buildingID) else { return }
        let refund = removed.definition.cost * world.rules.demolitionRefundPercent / 100
        world.book(refund, as: .refunds, detail: .building(removed.definition.id))

        // Lines no longer call at a demolished stop.
        if removed.category == .stop {
            for index in world.lines.indices {
                world.lines[index].stops.removeAll { $0 == buildingID }
            }
            for index in world.vehicles.indices {
                world.vehicles[index].route = []
                world.vehicles[index].stopIndex = 0
            }
        }

        // Carriers heading to the demolished building turn back; their cargo is lost.
        for index in world.carriers.indices where world.carriers[index].targetID == buildingID {
            world.carriers[index].turnBack()
        }
        WorkforceSystem.assignWorkers(in: &world)
        world.emit(.buildingDemolished(removed.definition.id, refund: refund))
    }
}
