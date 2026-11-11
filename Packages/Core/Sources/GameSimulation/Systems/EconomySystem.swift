import GameDomain

/// Records the daily balance and settles taxes and upkeep at the end of each year.
public struct EconomySystem: SimulationSystem {
    public init() {}

    public func update(_ world: inout WorldState) {
        if world.clock.isStartOfPeriod(days: 1) {
            world.ledger.recordBalance(world.treasury, day: world.clock.day)
        }
        guard world.clock.isStartOfPeriod(days: world.rules.daysPerYear) else { return }

        var taxes = 0
        var upkeepByType: [BuildingTypeID: Int] = [:]
        // Towns pay for their own stops.
        for building in world.buildings where building.townID == nil {
            upkeepByType[building.definition.id, default: 0] += building.definition.upkeepPerYear
            if building.supplyRatio >= 0.5 {
                taxes += building.residents * (building.definition.taxPerResidentPerYear ?? world.rules.taxPerResidentPerYear)
            }
        }
        var vehicleUpkeepByType: [VehicleTypeID: Int] = [:]
        for vehicle in world.vehicles {
            vehicleUpkeepByType[vehicle.definition.id, default: 0] += vehicle.definition.upkeepPerYear
        }

        // The year that just ended is settled in its last month; the clock already shows the new year.
        let closedYear = world.clock.year - 1
        let lastMonth = GameClock.monthsPerYear - 1
        world.book(taxes, as: .taxes, year: closedYear, month: lastMonth)
        for type in upkeepByType.keys.sorted() {
            world.book(-upkeepByType[type, default: 0], as: .upkeep, year: closedYear, month: lastMonth, detail: .building(type))
        }
        for type in vehicleUpkeepByType.keys.sorted() {
            world.book(-vehicleUpkeepByType[type, default: 0], as: .vehicles, year: closedYear, month: lastMonth, detail: .vehicle(type))
        }
        let upkeep = upkeepByType.values.reduce(0, +)
        world.emit(.yearClosed(year: world.clock.year, taxes: taxes, upkeep: upkeep))
    }
}
