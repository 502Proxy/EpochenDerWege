import GameDomain

/// Something noteworthy that happened in the world.
///
/// Events carry data, not text, so the presentation layer decides how to phrase and
/// localize them (observer pattern: the UI reads new events from each snapshot).
public enum SimulationEvent: Hashable, Sendable {
    case settlementFounded(population: Int)
    case buildingPlaced(BuildingTypeID, cost: Int)
    case buildingDemolished(BuildingTypeID, refund: Int)
    case placementRejected(PlacementError)
    case residentLeft(BuildingID)
    case yearClosed(year: Int, taxes: Int, upkeep: Int)
    case roadBuilt(cells: Int, cost: Int)
    case roadDemolished(cells: Int, refund: Int)
}

/// An event with its position in the event stream.
public struct EventRecord: Hashable, Sendable, Identifiable {
    /// Strictly increasing across the game. Readers remember the last sequence they handled.
    public let sequence: Int
    public let tick: Int
    public let event: SimulationEvent

    public var id: Int { sequence }
}
