/// Why a building cannot be placed on a cell.
public enum PlacementError: Error, Hashable, Sendable, Codable {
    case unknownBuildingType(BuildingTypeID)
    case outOfBounds
    case water
    case tooSteep(slopePercent: Double)
    case occupied
    case insufficientFunds(cost: Int)
    case missingResource(Biome)
}
