import GameDomain

/// How much a town wants to build in a kind of zone, from 0 (nothing) to 1 (urgent).
///
/// The same values drive ``TownGrowthSystem``: a town builds in a zone when its
/// demand reaches ``growthThreshold``. The HUD shows them as demand bars, so what
/// the player sees is exactly what the town does.
public struct ZoneDemand: Hashable, Sendable {
    /// Demand from 0 to 1.
    public var value: Double
    /// Why the demand is what it is.
    public var reason: Reason
    /// The town wants to build but finds no free zoned cell next to a road.
    public var lacksSpace: Bool

    public enum Reason: Hashable, Sendable {
        /// Nothing drives growth.
        case none
        /// More jobs than residents (residential).
        case openJobs(Int)
        /// Food is stored and houses are well supplied (residential).
        case foodSurplus
        /// Not enough food stored or houses badly supplied (residential).
        case lackOfFood
        /// A new house is waiting for its first residents (residential).
        case waitingForResidents
        /// The population supports more markets or workshops (commercial, industrial).
        case population
        /// No building of this zone is unlocked yet.
        case locked
    }

    /// Towns build at this demand or above.
    public static let growthThreshold = 0.5
    /// Average supply of existing houses required before food alone drives growth.
    public static let requiredSupply = 0.75

    public init(value: Double, reason: Reason, lacksSpace: Bool = false) {
        self.value = min(1, max(0, value))
        self.reason = reason
        self.lacksSpace = lacksSpace
    }

    public var isGrowing: Bool {
        value >= Self.growthThreshold
    }

    // MARK: - Computing

    /// Demand for one kind of zone. Checking for free space scans the zone, so it is
    /// only done when the town actually wants to grow.
    public static func compute(for kind: ZoneKind, in world: WorldState) -> ZoneDemand {
        var demand: ZoneDemand
        var wanted: [BuildingDefinition] = []
        switch kind {
        case .residential:
            demand = residential(in: world)
            if demand.isGrowing, let house = world.catalog.firstBuilding(of: .housing) {
                wanted = [house]
            }
        case .commercial, .industrial:
            let definitions = world.catalog.buildings(forZone: kind).filter { ($0.requiredLevel ?? 0) <= world.settlementLevel }
            guard !definitions.isEmpty else { return ZoneDemand(value: 0, reason: .locked) }
            let values = definitions.map { (definition: $0, value: commerceValue(for: $0, in: world)) }
            demand = ZoneDemand(value: values.map(\.value).max() ?? 0, reason: .population)
            wanted = values.filter { $0.value >= growthThreshold }.map(\.definition)
            if !demand.isGrowing && demand.value == 0 {
                demand.reason = .none
            }
        }
        demand.lacksSpace = wanted.contains { TownGrowthSystem.bestBuildingSite(for: $0, in: kind, world: world) == nil }
        return demand
    }

    /// Open jobs or a food surplus with well supplied houses make the town grow; an
    /// empty house holds growth back until it is moved into.
    static func residential(in world: WorldState) -> ZoneDemand {
        let houses = world.buildings.filter { $0.category == .housing }
        if houses.contains(where: { $0.residents == 0 }) {
            return ZoneDemand(value: 0.3, reason: .waitingForResidents)
        }

        let openJobs = world.workersNeeded - world.population
        if openJobs > 0 {
            return ZoneDemand(value: 0.5 + 0.5 * min(1, Double(openJobs) / 10), reason: .openJobs(openJobs))
        }

        let rules = world.rules
        let storedFood = rules.foodGoods.reduce(0) { $0 + world.storedAmount(of: $1) }
        let foodShare = rules.zoneGrowthFoodThreshold > 0
            ? Double(storedFood) / Double(rules.zoneGrowthFoodThreshold)
            : .infinity
        let averageSupply = houses.isEmpty ? 1 : houses.reduce(0) { $0 + $1.supplyRatio } / Double(houses.count)
        let supplyShare = averageSupply / requiredSupply

        if foodShare >= 1 && supplyShare >= 1 {
            return ZoneDemand(value: 0.5 + 0.5 * min(1, (foodShare - 1) / 2), reason: .foodSurplus)
        }
        let share = min(foodShare, supplyShare)
        return ZoneDemand(value: 0.49 * min(1, share), reason: share > 0 ? .lackOfFood : .none)
    }

    /// One building per `residentsPerBuilding` residents: the demand passes the growth
    /// threshold exactly when the population supports one more.
    static func commerceValue(for definition: BuildingDefinition, in world: WorldState) -> Double {
        guard let residentsPerBuilding = definition.residentsPerBuilding, residentsPerBuilding > 0 else { return 0 }
        let existing = world.buildings.filter { $0.definition.id == definition.id }.count
        let missing = Double(world.population) / Double(residentsPerBuilding) - Double(existing)
        // Integer check, so rounding can never disagree with the town's decision.
        if world.population / residentsPerBuilding > existing {
            return 0.5 + 0.5 * min(1, (missing - 1) / 2)
        }
        return 0.49 * max(0, missing)
    }
}
