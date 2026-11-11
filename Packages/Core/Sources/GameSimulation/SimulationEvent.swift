import GameDomain

/// Something noteworthy that happened in the world.
///
/// Events carry data, not text, so the presentation layer decides how to phrase and
/// localize them (observer pattern: the UI reads new events from each snapshot).
public enum SimulationEvent: Hashable, Sendable, Codable {
    case settlementFounded(population: Int)
    case buildingPlaced(BuildingTypeID, cost: Int)
    case buildingDemolished(BuildingTypeID, refund: Int)
    case placementRejected(PlacementError)
    case residentLeft(BuildingID)
    case yearClosed(year: Int, taxes: Int, upkeep: Int)
    case roadBuilt(cells: Int, cost: Int)
    case roadDemolished(cells: Int, refund: Int)
    case zoneChanged(kind: ZoneKind?, cells: Int)
    case townGrew(BuildingID)
    case lineCreated(LineID)
    case lineDeleted(LineID)
    /// A line needs at least two different stops.
    case lineRejected
    case vehicleBought(VehicleTypeID, cost: Int)
    case vehicleSold(VehicleTypeID, refund: Int)
    /// The settlement grew into a new size class (index into the catalog's levels).
    case settlementLevelReached(Int)
    /// A house moved up to the next tier.
    case houseUpgraded(BuildingID, to: BuildingTypeID)
    /// A house dropped to the previous tier because a need was missing.
    case houseDowngraded(BuildingID, to: BuildingTypeID)
}

/// An event with its position in the event stream.
public struct EventRecord: Hashable, Sendable, Identifiable, Codable {
    /// Strictly increasing across the game. Readers remember the last sequence they handled.
    public let sequence: Int
    public let tick: Int
    public let event: SimulationEvent

    public var id: Int { sequence }
}
