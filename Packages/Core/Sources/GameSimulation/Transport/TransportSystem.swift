import GameDomain

/// Where goods are wanted around stops.
///
/// A good is *wanted* near a stop when a consumer within carrier range of the stop
/// needs it: a production input, food for a house or stock for a market or workshop.
/// Storehouses do not count, otherwise goods would shuttle between storehouses forever.
enum StopDemand {
    static func isWanted(_ good: GoodID, near stopID: BuildingID, in world: WorldState) -> Bool {
        guard let stop = world.building(stopID) else { return false }
        // A town's stop wants what the town buys.
        if let townID = stop.townID {
            return world.town(townID)?.buys(good) ?? false
        }
        let range = world.rules.carrierRangeMeters
        return world.buildings.contains { building in
            building.category != .stop
                && building.category != .storage
                && stop.center.distance(to: building.center) <= range
                && NearestConsumerPlanner.demand(of: building, for: good, in: world) > 0
        }
    }

    /// Whether a line calling at this stop takes the good to another stop where it is wanted.
    static func canExport(_ good: GoodID, from stopID: BuildingID, in world: WorldState) -> Bool {
        world.lines(servingStop: stopID).contains { line in
            line.stops.contains { $0 != stopID && isWanted(good, near: $0, in: world) }
        }
    }
}

/// Drives vehicles along their lines and exchanges cargo at stops.
///
/// A vehicle drives from stop to stop in line order and then starts over. Routes are
/// found on the road network when the vehicle leaves a stop. At every stop it
/// unloads goods that are wanted there (or nowhere else on the line) and loads goods
/// that another stop on the line wants.
public struct TransportSystem: SimulationSystem {
    /// Ticks a vehicle waits at each stop.
    public static let dwellTicks = 10

    public init() {}

    public func update(_ world: inout WorldState) {
        let ticksPerDay = Double(world.rules.ticksPerDay)
        for index in world.vehicles.indices {
            var vehicle = world.vehicles[index]
            advance(&vehicle, ticksPerDay: ticksPerDay, world: &world)
            world.vehicles[index] = vehicle
        }
    }

    private func advance(_ vehicle: inout Vehicle, ticksPerDay: Double, world: inout WorldState) {
        guard let line = world.line(vehicle.lineID), line.stops.count >= 2 else {
            vehicle.status = .idle
            vehicle.route = []
            return
        }
        if vehicle.stopIndex >= line.stops.count {
            vehicle.stopIndex = 0
        }

        if vehicle.route.isEmpty {
            if vehicle.dwellTicks > 0 {
                vehicle.dwellTicks -= 1
                vehicle.status = .loading
                return
            }
            let next = (vehicle.stopIndex + 1) % line.stops.count
            guard
                let origin = world.building(line.stops[vehicle.stopIndex]),
                let destination = world.building(line.stops[next]),
                let route = RoadNetwork.route(from: origin, to: destination, in: world)
            else {
                // Try again in a day; the player may still be building the road.
                vehicle.status = .noRoute
                vehicle.dwellTicks = world.rules.ticksPerDay
                return
            }
            vehicle.route = route
            vehicle.driven = 0
            vehicle.status = .driving
        }

        vehicle.driven += vehicle.definition.speedMetersPerDay / ticksPerDay
        if vehicle.driven >= Route.length(of: vehicle.route) {
            vehicle.stopIndex = (vehicle.stopIndex + 1) % line.stops.count
            vehicle.route = []
            vehicle.driven = 0
            vehicle.dwellTicks = Self.dwellTicks
            vehicle.status = .loading
            if let stopIndex = world.index(of: line.stops[vehicle.stopIndex]) {
                vehicle.position = world.buildings[stopIndex].center
                Self.exchangeCargo(&vehicle, atBuildingIndex: stopIndex, line: line, world: &world)
            }
        } else if let position = Route.point(on: vehicle.route, at: vehicle.driven) {
            vehicle.position = position
        }
    }

    static func exchangeCargo(_ vehicle: inout Vehicle, atBuildingIndex stopIndex: Int, line: TransportLine, world: inout WorldState) {
        let stopID = world.buildings[stopIndex].id
        let otherStops = line.stops.filter { $0 != stopID }

        if let townID = world.buildings[stopIndex].townID {
            TradeSystem.trade(&vehicle, withTown: townID, atBuildingIndex: stopIndex, otherStops: otherStops, world: &world)
            return
        }

        // Unload what is wanted here, or what no other stop on the line wants any more.
        for good in vehicle.cargo.keys.sorted() {
            let amount = vehicle.cargo[good, default: 0]
            let wantedHere = StopDemand.isWanted(good, near: stopID, in: world)
            let wantedElsewhere = otherStops.contains { StopDemand.isWanted(good, near: $0, in: world) }
            guard amount > 0, wantedHere || !wantedElsewhere else { continue }
            let unloaded = world.buildings[stopIndex].output.add(good, amount: amount)
            let rest = amount - unloaded
            vehicle.cargo[good] = rest > 0 ? rest : nil
        }

        // Load what another stop on the line wants.
        for item in world.buildings[stopIndex].output.sortedItems where vehicle.freeCapacity > 0 {
            guard otherStops.contains(where: { StopDemand.isWanted(item.good, near: $0, in: world) }) else { continue }
            let taken = world.buildings[stopIndex].output.remove(item.good, amount: min(item.amount, vehicle.freeCapacity))
            vehicle.cargo[item.good, default: 0] += taken
        }
    }
}
