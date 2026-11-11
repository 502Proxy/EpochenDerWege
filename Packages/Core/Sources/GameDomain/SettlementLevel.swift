/// A size class of the player's settlement, such as hamlet or village.
///
/// Levels are reached by population and are kept once reached, so a short famine
/// never takes unlocked buildings away. Buildings can require a level
/// (``BuildingDefinition/requiredLevel``).
public struct SettlementLevel: Hashable, Sendable, Codable {
    public var id: String
    /// English display name. The app localizes it through its string catalog.
    public var name: String
    /// Residents needed to reach this level.
    public var minimumPopulation: Int

    public init(id: String, name: String, minimumPopulation: Int) {
        self.id = id
        self.name = name
        self.minimumPopulation = minimumPopulation
    }

    /// Used when a catalog defines no levels: everything is available from the start.
    public static let single = SettlementLevel(id: "settlement", name: "Settlement", minimumPopulation: 0)
}
