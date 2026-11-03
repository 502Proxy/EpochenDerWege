import GameDomain

/// Runs production cycles: consumes inputs, advances progress, produces outputs.
public struct ProductionSystem: SimulationSystem {
    public init() {}

    public func update(_ world: inout WorldState) {
        let ticksPerDay = Double(world.rules.ticksPerDay)
        for index in world.buildings.indices {
            var building = world.buildings[index]
            switch building.category {
            case .housing:
                building.status = .housing
            case .storage:
                building.status = .storing
            case .production:
                Self.advance(&building, ticksPerDay: ticksPerDay)
            }
            world.buildings[index] = building
        }
    }

    static func advance(_ building: inout Building, ticksPerDay: Double) {
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
                building.input.remove(input.good, amount: input.amount)
            }
            building.isCycleRunning = true
            building.progress = 0
        }

        building.status = .working
        building.progress += building.efficiency / (max(0.1, definition.cycleDays) * ticksPerDay)
        if building.progress >= 1 {
            for output in definition.outputs {
                building.output.add(output.good, amount: output.amount)
            }
            building.progress = 0
            building.isCycleRunning = false
        }
    }
}
