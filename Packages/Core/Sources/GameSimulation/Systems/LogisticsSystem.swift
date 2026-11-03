import GameDomain

/// Where a carrier should take a good.
public struct DeliveryTarget: Hashable, Sendable {
    public let buildingID: BuildingID
    /// How many units the target can still accept.
    public let capacity: Int

    public init(buildingID: BuildingID, capacity: Int) {
        self.buildingID = buildingID
        self.capacity = capacity
    }
}

/// Chooses delivery targets for carriers (strategy pattern).
///
/// Swapping the planner changes how goods are distributed without touching the
/// logistics system, e.g. for road-based routing in a later milestone.
public protocol DeliveryPlanner: Sendable {
    func target(for good: GoodID, from source: Building, in world: WorldState) -> DeliveryTarget?
}

/// Default planner for the prototype.
///
/// 1. Consumers that need the good (production inputs, house food) come first.
/// 2. Among houses, those with little food are preferred so shortages are shared fairly.
/// 3. Commerce buildings (markets, workshops) buy what consumers do not need.
/// 4. Storehouses take whatever nobody in range buys.
public struct NearestConsumerPlanner: DeliveryPlanner {
    /// Extra "distance" in metres per unit of food a house already has.
    public var houseStockPenaltyMeters: Double

    public init(houseStockPenaltyMeters: Double = 40) {
        self.houseStockPenaltyMeters = houseStockPenaltyMeters
    }

    public func target(for good: GoodID, from source: Building, in world: WorldState) -> DeliveryTarget? {
        let rules = world.rules
        var best: (target: DeliveryTarget, score: Double)?

        for candidate in world.buildings where candidate.id != source.id {
            if source.category == .storage && candidate.category == .storage { continue }
            let capacity = Self.demand(of: candidate, for: good, rules: rules)
            guard capacity > 0 else { continue }
            let distance = source.center.distance(to: candidate.center)
            guard distance <= rules.carrierRangeMeters else { continue }

            var score = distance
            switch candidate.category {
            case .storage:
                score += rules.carrierRangeMeters * 2
            case .commerce:
                score += rules.carrierRangeMeters
            case .housing:
                let stock = rules.foodGoods.reduce(0) { $0 + candidate.input.count(of: $1) + candidate.incomingAmount(of: $1) }
                score += Double(stock) * houseStockPenaltyMeters
            case .production:
                break
            }

            if best.map({ score < $0.score }) ?? true {
                best = (DeliveryTarget(buildingID: candidate.id, capacity: capacity), score)
            }
        }
        return best?.target
    }

    /// Units of `good` a building still accepts, minus what is already on its way.
    static func demand(of building: Building, for good: GoodID, rules: GameRules) -> Int {
        let incoming = building.incomingAmount(of: good)
        switch building.category {
        case .production:
            guard building.definition.consumes(good) else { return 0 }
            return building.input.space(for: good) - incoming
        case .housing:
            guard rules.foodGoods.contains(good) else { return 0 }
            return building.input.space(for: good) - incoming
        case .commerce:
            guard building.definition.consumes(good) else { return 0 }
            return building.input.space(for: good) - incoming
        case .storage:
            return building.output.space(for: good) - incoming
        }
    }
}

/// Sends carriers from buildings with output to buildings that need it, and moves them.
public struct LogisticsSystem: SimulationSystem {
    public let planner: any DeliveryPlanner

    public init(planner: any DeliveryPlanner = NearestConsumerPlanner()) {
        self.planner = planner
    }

    public func update(_ world: inout WorldState) {
        if world.clock.isMultiple(ofTicks: world.rules.dispatchIntervalTicks) {
            dispatchCarriers(in: &world)
        }
        moveCarriers(in: &world)
    }

    private func dispatchCarriers(in world: inout WorldState) {
        for sourceIndex in world.buildings.indices where world.buildings[sourceIndex].definition.maxCarriers > 0 {
            var freeSlots = world.buildings[sourceIndex].definition.maxCarriers - world.buildings[sourceIndex].activeCarriers
            guard freeSlots > 0 else { continue }

            for stock in world.buildings[sourceIndex].output.sortedItems where stock.amount > 0 {
                guard freeSlots > 0 else { break }
                let source = world.buildings[sourceIndex]
                guard
                    let target = planner.target(for: stock.good, from: source, in: world),
                    let targetIndex = world.index(of: target.buildingID)
                else { continue }

                let amount = min(world.rules.carrierCapacity, stock.amount, target.capacity)
                guard amount > 0 else { continue }

                world.buildings[sourceIndex].output.remove(stock.good, amount: amount)
                world.buildings[sourceIndex].activeCarriers += 1
                world.buildings[targetIndex].incoming[stock.good, default: 0] += amount
                freeSlots -= 1

                let carrier = Carrier(
                    id: world.makeCarrierID(),
                    cargo: GoodAmount(good: stock.good, amount: amount),
                    sourceID: source.id,
                    targetID: target.buildingID,
                    origin: source.center,
                    destination: world.buildings[targetIndex].center
                )
                world.carriers.append(carrier)
            }
        }
    }

    private func moveCarriers(in world: inout WorldState) {
        let step = world.rules.carrierSpeedMetersPerDay / Double(world.rules.ticksPerDay)
        var finished = Set<CarrierID>()

        for index in world.carriers.indices {
            world.carriers[index].walked += step
            let carrier = world.carriers[index]
            guard carrier.walked >= carrier.distance else { continue }

            switch carrier.phase {
            case .delivering:
                deliver(carrier, in: &world)
                world.carriers[index].phase = .returning
                world.carriers[index].walked = 0
            case .returning:
                finished.insert(carrier.id)
                if let sourceIndex = world.index(of: carrier.sourceID) {
                    world.buildings[sourceIndex].activeCarriers = max(0, world.buildings[sourceIndex].activeCarriers - 1)
                }
            }
        }

        if !finished.isEmpty {
            world.carriers.removeAll { finished.contains($0.id) }
        }
    }

    private func deliver(_ carrier: Carrier, in world: inout WorldState) {
        // The target may have been demolished; the cargo is then lost.
        guard let index = world.index(of: carrier.targetID) else { return }
        let good = carrier.cargo.good
        world.buildings[index].incoming[good] = max(0, world.buildings[index].incomingAmount(of: good) - carrier.cargo.amount)
        switch world.buildings[index].category {
        case .storage:
            world.buildings[index].output.add(good, amount: carrier.cargo.amount)
        case .production, .housing:
            world.buildings[index].input.add(good, amount: carrier.cargo.amount)
        case .commerce:
            // Markets and workshops pay the base price for every delivered unit.
            let accepted = world.buildings[index].input.add(good, amount: carrier.cargo.amount)
            let price = world.catalog.good(good)?.basePrice ?? 0
            world.book(accepted * price, as: .sales)
        }
    }
}
