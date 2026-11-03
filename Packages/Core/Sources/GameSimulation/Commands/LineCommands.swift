import GameDomain

/// Creates a line through the given stops, in order. Needs at least two different stops.
public struct CreateLineCommand: GameCommand {
    public let stops: [BuildingID]

    public init(stops: [BuildingID]) {
        self.stops = stops
    }

    public func execute(in world: inout WorldState) {
        var seen = Set<BuildingID>()
        let valid = stops.filter { id in
            world.building(id)?.category == .stop && seen.insert(id).inserted
        }
        guard valid.count >= 2 else {
            world.emit(.lineRejected)
            return
        }
        let line = TransportLine(id: world.makeLineID(), stops: valid)
        world.lines.append(line)
        world.emit(.lineCreated(line.id))
    }
}

/// Deletes a line and sells its vehicles.
public struct DeleteLineCommand: GameCommand {
    public let lineID: LineID

    public init(lineID: LineID) {
        self.lineID = lineID
    }

    public func execute(in world: inout WorldState) {
        guard world.line(lineID) != nil else { return }
        let refund = world.vehicles
            .filter { $0.lineID == lineID }
            .reduce(0) { $0 + $1.definition.price * world.rules.demolitionRefundPercent / 100 }
        world.vehicles.removeAll { $0.lineID == lineID }
        world.lines.removeAll { $0.id == lineID }
        world.book(refund, as: .refunds)
        world.emit(.lineDeleted(lineID))
    }
}

/// Buys a vehicle for a line. It starts at the line's first stop.
public struct BuyVehicleCommand: GameCommand {
    public let lineID: LineID
    public let vehicleType: VehicleTypeID

    public init(lineID: LineID, vehicleType: VehicleTypeID) {
        self.lineID = lineID
        self.vehicleType = vehicleType
    }

    public func execute(in world: inout WorldState) {
        guard
            let line = world.line(lineID),
            let definition = world.catalog.vehicle(vehicleType),
            let firstStop = line.stops.first.flatMap({ world.building($0) })
        else { return }
        guard world.treasury >= definition.price else {
            world.emit(.placementRejected(.insufficientFunds(cost: definition.price)))
            return
        }
        world.book(-definition.price, as: .vehicles, detail: .vehicle(definition.id))
        let vehicle = Vehicle(id: world.makeVehicleID(), definition: definition, lineID: lineID, position: firstStop.center)
        world.vehicles.append(vehicle)
        world.emit(.vehicleBought(vehicleType, cost: definition.price))
    }
}

/// Sells the newest vehicle of a line for half its price. Its cargo is lost.
public struct SellVehicleCommand: GameCommand {
    public let lineID: LineID

    public init(lineID: LineID) {
        self.lineID = lineID
    }

    public func execute(in world: inout WorldState) {
        guard let index = world.vehicles.lastIndex(where: { $0.lineID == lineID }) else { return }
        let vehicle = world.vehicles.remove(at: index)
        let refund = vehicle.definition.price * world.rules.demolitionRefundPercent / 100
        world.book(refund, as: .refunds)
        world.emit(.vehicleSold(vehicle.definition.id, refund: refund))
    }
}
