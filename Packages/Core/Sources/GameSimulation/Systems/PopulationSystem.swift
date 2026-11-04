import GameDomain

/// Feeds houses, grows or shrinks their population.
public struct PopulationSystem: SimulationSystem {
    public init() {}

    public func update(_ world: inout WorldState) {
        guard world.clock.isStartOfPeriod(days: world.rules.supplyCheckIntervalDays) else { return }
        let rules = world.rules
        let year = world.clock.year
        var departures: [BuildingID] = []

        for index in world.buildings.indices where world.buildings[index].category == .housing {
            var house = world.buildings[index]
            if Self.checkSupply(of: &house, rules: rules, statistics: &world.goodsStatistics, year: year) == .shrank {
                departures.append(house.id)
            }
            world.buildings[index] = house
        }

        for id in departures {
            world.emit(.residentLeft(id))
        }
        WorkforceSystem.assignWorkers(in: &world)
    }

    enum Outcome: Equatable {
        case grew, stable, shrank
    }

    static func checkSupply(of house: inout Building, rules: GameRules, statistics: inout GoodsStatistics, year: Int) -> Outcome {
        let hasFood = rules.foodGoods.contains { house.input.count(of: $0) > 0 }

        // Empty houses are moved into again as soon as food arrives.
        guard house.residents > 0 else {
            house.supplyRatio = hasFood ? 1 : 0
            if hasFood {
                house.residents = 1
                return .grew
            }
            return .stable
        }

        let need = Double(house.residents) * rules.foodPerResidentPerCheck
        house.unpaidFood += need
        var eaten = 0.0
        while house.unpaidFood >= 1, let good = rules.foodGoods.first(where: { house.input.count(of: $0) > 0 }) {
            house.input.remove(good, amount: 1)
            statistics.recordConsumed(good, amount: 1, year: year)
            house.unpaidFood -= 1
            eaten += 1
        }

        // More than one unit left unpaid means there was not enough food.
        let starving = house.unpaidFood >= 1
        house.supplyRatio = starving ? min(1, eaten / need) : 1
        // No debt: what could not be eaten today is gone.
        house.unpaidFood = min(house.unpaidFood, 0.99)

        if house.supplyRatio >= 0.9 && house.residents < house.definition.maxResidents {
            house.residents += 1
            return .grew
        }
        if house.supplyRatio < 0.5 {
            house.residents -= 1
            return .shrank
        }
        return .stable
    }
}
