import GameDomain

/// Changes the player's settings of a building. `nil` leaves a setting unchanged.
public struct ConfigureBuildingCommand: GameCommand {
    public let buildingID: BuildingID
    public let isPaused: Bool?
    public let priority: DeliveryPriority?

    public init(buildingID: BuildingID, isPaused: Bool? = nil, priority: DeliveryPriority? = nil) {
        self.buildingID = buildingID
        self.isPaused = isPaused
        self.priority = priority
    }

    public func execute(in world: inout WorldState) {
        guard let index = world.index(of: buildingID), world.buildings[index].isConfigurable else { return }
        if let isPaused {
            world.buildings[index].isPaused = isPaused
        }
        if let priority {
            world.buildings[index].priority = priority
        }
        WorkforceSystem.assignWorkers(in: &world)
    }
}
