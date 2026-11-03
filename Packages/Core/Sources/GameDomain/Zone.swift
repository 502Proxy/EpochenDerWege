/// Purpose of a zoned area. Towns build matching buildings inside zones on their own.
public enum ZoneKind: String, CaseIterable, Hashable, Sendable, Codable {
    /// Houses appear here when the town has demand.
    case residential
}
