/// A carrier walks goods from one building to another and then walks back empty.
public struct Carrier: Identifiable, Hashable, Sendable, Codable {
    public enum Phase: Hashable, Sendable, Codable {
        case delivering
        case returning
    }

    public let id: CarrierID
    public let cargo: GoodAmount
    public let sourceID: BuildingID
    public let targetID: BuildingID
    public let origin: WorldPoint
    public let destination: WorldPoint
    public let distance: Double
    public var phase: Phase = .delivering
    /// Metres walked in the current phase.
    public var walked: Double = 0

    public init(
        id: CarrierID,
        cargo: GoodAmount,
        sourceID: BuildingID,
        targetID: BuildingID,
        origin: WorldPoint,
        destination: WorldPoint
    ) {
        self.id = id
        self.cargo = cargo
        self.sourceID = sourceID
        self.targetID = targetID
        self.origin = origin
        self.destination = destination
        distance = origin.distance(to: destination)
    }

    public var isLoaded: Bool { phase == .delivering }

    /// Current position on the ground.
    public var position: WorldPoint {
        let t = distance > 0 ? min(1, walked / distance) : 1
        switch phase {
        case .delivering:
            return origin.interpolated(to: destination, fraction: t)
        case .returning:
            return destination.interpolated(to: origin, fraction: t)
        }
    }

    /// Turns the carrier around on the spot, for example when its target was demolished.
    public mutating func turnBack() {
        guard phase == .delivering else { return }
        phase = .returning
        walked = max(0, distance - walked)
    }
}
