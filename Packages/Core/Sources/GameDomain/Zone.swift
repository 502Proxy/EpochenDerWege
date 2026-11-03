/// Purpose of a zoned area. Towns build matching buildings inside zones on their own.
public enum ZoneKind: String, CaseIterable, Hashable, Sendable, Codable {
    /// Houses appear here when the town has demand.
    case residential
    /// Markets appear here; they buy food and consumer goods.
    case commercial
    /// Workshops appear here; they buy raw materials.
    case industrial
}
