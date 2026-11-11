import GameDomain

/// Rules for house tiers: what a house needs, and when it moves up or down.
///
/// Every tier needs food. Higher tiers also need goods like clothing or wine
/// (``BuildingDefinition/needs``). A house moves up when it is full, well fed, the
/// settlement level allows the next tier and it has kept all goods of the next
/// tier in stock for ``GameRules/upgradeChecks`` supply checks in a row. It drops a
/// tier when one of its own needs is missing for ``GameRules/downgradeChecks`` checks.
enum HouseTiers {
    enum Change: Equatable {
        case upgraded(BuildingTypeID)
        case downgraded(BuildingTypeID)
    }

    /// Whether a house accepts a good besides food: its own needs and, once that tier
    /// is unlocked, the needs of the next tier.
    static func wants(_ good: GoodID, house: Building, in world: WorldState) -> Bool {
        if house.definition.needs?.contains(good) == true {
            return true
        }
        guard let next = unlockedNextTier(of: house, in: world) else { return false }
        return next.needs?.contains(good) == true
    }

    static func unlockedNextTier(of house: Building, in world: WorldState) -> BuildingDefinition? {
        guard let next = world.catalog.nextTier(of: house.definition),
              (next.requiredLevel ?? 0) <= world.settlementLevel
        else { return nil }
        return next
    }

    /// Units of one need a house uses per supply check.
    static func needUnits(residents: Int, rules: GameRules) -> Int {
        max(1, Int((Double(residents) * rules.needPerResidentPerCheck).rounded()))
    }

    /// Consumes the house's needs and moves it up or down a tier when due.
    /// Called once per supply check after food was eaten.
    static func check(_ house: inout Building, in world: WorldState, statistics: inout GoodsStatistics) -> Change? {
        guard house.residents > 0 else { return nil }
        let rules = world.rules
        let year = world.clock.year

        // Use up the current tier's needs.
        var allMet = true
        let units = needUnits(residents: house.residents, rules: rules)
        for good in house.definition.needs ?? [] {
            let used = house.input.remove(good, amount: units)
            if used > 0 {
                statistics.recordConsumed(good, amount: used, year: year)
            }
            if used < units {
                allMet = false
            }
        }

        if !allMet {
            house.upgradeProgress = 0
            house.missingNeedChecks += 1
            if house.missingNeedChecks >= rules.downgradeChecks, let previous = world.catalog.previousTier(of: house.definition) {
                house.convert(to: previous)
                return .downgraded(previous.id)
            }
            return nil
        }
        house.missingNeedChecks = 0

        // Move up when full, fed and stocked with everything the next tier needs.
        guard
            let next = unlockedNextTier(of: house, in: world),
            house.residents >= house.definition.maxResidents,
            house.supplyRatio >= 0.9,
            (next.needs ?? []).filter({ !(house.definition.needs ?? []).contains($0) }).allSatisfy({ house.input.count(of: $0) > 0 })
        else {
            house.upgradeProgress = 0
            return nil
        }
        house.upgradeProgress += 1
        guard house.upgradeProgress >= rules.upgradeChecks else { return nil }
        house.convert(to: next)
        return .upgraded(next.id)
    }
}
