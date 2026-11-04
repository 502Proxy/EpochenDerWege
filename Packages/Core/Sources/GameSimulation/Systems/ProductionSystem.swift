import GameDomain

/// Runs production cycles: consumes inputs, advances progress, produces outputs.
public struct ProductionSystem: SimulationSystem {
    public init() {}

    public func update(_ world: inout WorldState) {
        let ticksPerDay = Double(world.rules.ticksPerDay)
        let year = world.clock.year
        for index in world.buildings.indices {
            var building = world.buildings[index]
            if building.isPaused {
                building.status = .paused
                world.buildings[index] = building
                continue
            }
            switch building.category {
            case .housing:
                building.status = .housing
            case .storage, .stop:
                building.status = .storing
            case .commerce:
                Self.trade(&building, ticksPerDay: ticksPerDay, statistics: &world.goodsStatistics, year: year)
            case .production:
                Self.advance(&building, ticksPerDay: ticksPerDay, statistics: &world.goodsStatistics, year: year)
            }
            world.buildings[index] = building
        }
    }

    /// Commerce buildings sell part of their stock to the townspeople every cycle,
    /// which frees space for further deliveries.
    static func trade(_ building: inout Building, ticksPerDay: Double, statistics: inout GoodsStatistics, year: Int) {
        let hasStock = building.definition.inputs.contains { building.input.count(of: $0.good) > 0 }
        building.status = hasStock ? .trading : .awaitingGoods
        guard hasStock else { return }
        building.progress += 1 / (max(0.1, building.definition.cycleDays) * ticksPerDay)
        if building.progress >= 1 {
            for input in building.definition.inputs {
                let sold = building.input.remove(input.good, amount: input.amount)
                statistics.recordConsumed(input.good, amount: sold, year: year)
            }
            building.progress = 0
        }
    }

    static func advance(_ building: inout Building, ticksPerDay: Double, statistics: inout GoodsStatistics, year: Int) {
        let definition = building.definition
        if definition.workers > 0 && building.assignedWorkers == 0 {
            building.status = .noWorkers
            return
        }
        if building.resourceFactor <= 0 {
            building.status = .noResources
            return
        }
        if !building.isCycleRunning {
            guard definition.outputs.allSatisfy({ building.output.space(for: $0.good) >= $0.amount }) else {
                building.status = .outputFull
                return
            }
            guard definition.inputs.allSatisfy({ building.input.contains($0) }) else {
                building.status = .missingInput
                return
            }
            for input in definition.inputs {
                let used = building.input.remove(input.good, amount: input.amount)
                statistics.recordConsumed(input.good, amount: used, year: year)
            }
            building.isCycleRunning = true
            building.progress = 0
        }

        building.status = .working
        building.progress += building.efficiency / (max(0.1, definition.cycleDays) * ticksPerDay)
        if building.progress >= 1 {
            for output in definition.outputs {
                let made = building.output.add(output.good, amount: output.amount)
                statistics.recordProduced(output.good, amount: made, year: year)
            }
            building.progress = 0
            building.isCycleRunning = false
        }
    }
}
