/// Why a building cannot be placed on a cell.
public enum PlacementError: Error, Hashable, Sendable, Codable {
    case unknownBuildingType(BuildingTypeID)
    case outOfBounds
    case water
    case tooSteep(slopePercent: Double)
    case occupied
    case insufficientFunds(cost: Int)
    case missingResource(Biome)
    /// The building needs a deposit (e.g. stone) nearby.
    case missingDeposit(Deposit)
    /// The building may only be placed in one of these zones.
    case requiresZone([ZoneKind])
    /// The building must stand next to a road.
    case noRoadAccess
    /// The settlement has not reached the level the building needs (index into the catalog's levels).
    case requiresLevel(Int)
}
