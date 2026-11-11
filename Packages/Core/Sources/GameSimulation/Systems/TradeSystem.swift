import GameDomain

/// Trade with neighbouring towns.
///
/// Every `tradeIntervalDays` each town puts the goods it produces on its stop and
/// renews the amounts it wants to buy. Vehicles that call at a town's stop sell what
/// the town wants, for `townPriceFactor` times the base price, and buy goods that
/// another stop on their line wants, for the base price.
public struct TradeSystem: SimulationSystem {
    public init() {}

    public func update(_ world: inout WorldState) {
        guard world.clock.isStartOfPeriod(days: world.rules.tradeIntervalDays) else { return }
        for townIndex in world.towns.indices {
            let town = world.towns[townIndex]
            world.towns[townIndex].wanted = Dictionary(town.template.buys.map { ($0.good, $0.amount) }, uniquingKeysWith: +)
            guard let stopIndex = world.index(of: town.stopID) else { continue }
            for offer in town.template.sells {
                world.buildings[stopIndex].output.add(offer.good, amount: offer.amount)
            }
        }
    }

    static func trade(_ vehicle: inout Vehicle, withTown townID: TownID, atBuildingIndex stopIndex: Int, otherStops: [BuildingID], world: inout WorldState) {
        guard let townIndex = world.towns.firstIndex(where: { $0.id == townID }) else { return }

        // Sell what the town wants.
        for good in vehicle.cargo.keys.sorted() {
            let wanted = world.towns[townIndex].wanted[good, default: 0]
            let sold = min(vehicle.cargo[good, default: 0], wanted)
            guard sold > 0 else { continue }
            vehicle.cargo[good] = vehicle.cargo[good, default: 0] - sold > 0 ? vehicle.cargo[good, default: 0] - sold : nil
            world.towns[townIndex].wanted[good] = wanted - sold
            let price = Double(world.catalog.good(good)?.basePrice ?? 0) * world.rules.townPriceFactor
            world.book(Int((Double(sold) * price).rounded()), as: .sales, detail: .good(good))
            world.goodsStatistics.recordConsumed(good, amount: sold, year: world.clock.year)
        }

        // Buy what another stop on the line wants.
        for item in world.buildings[stopIndex].output.sortedItems where vehicle.freeCapacity > 0 {
            guard otherStops.contains(where: { StopDemand.isWanted(item.good, near: $0, in: world) }) else { continue }
            let taken = world.buildings[stopIndex].output.remove(item.good, amount: min(item.amount, vehicle.freeCapacity))
            guard taken > 0 else { continue }
            vehicle.cargo[item.good, default: 0] += taken
            let price = world.catalog.good(item.good)?.basePrice ?? 0
            world.book(-taken * price, as: .purchases, detail: .good(item.good))
        }
    }
}
