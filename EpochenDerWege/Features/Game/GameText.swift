import Foundation
import GameDomain
import GameSimulation

/// Turns domain values into localized, player-facing text.
///
/// The domain never contains display strings beyond the English names in the game
/// data. All phrasing lives here and in `Localizable.xcstrings`.
enum GameText {
    // MARK: - Names

    static func name(of building: BuildingDefinition) -> String {
        String(localized: String.LocalizationValue(building.name))
    }

    static func buildingName(_ id: BuildingTypeID, in catalog: GameCatalog) -> String {
        catalog.building(id).map(name(of:)) ?? id.rawValue
    }

    static func goodName(_ id: GoodID, in catalog: GameCatalog) -> String {
        guard let good = catalog.good(id) else { return id.rawValue }
        return String(localized: String.LocalizationValue(good.name))
    }

    static func name(of biome: Biome) -> String {
        switch biome {
        case .water: String(localized: "Water")
        case .sand: String(localized: "Sand")
        case .grass: String(localized: "Grassland")
        case .forest: String(localized: "Forest")
        case .rock: String(localized: "Rock")
        case .snow: String(localized: "Snow")
        }
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    // MARK: - Messages

    static func message(for error: PlacementError, catalog: GameCatalog) -> String {
        switch error {
        case .unknownBuildingType(let id):
            String(localized: "Unknown building \(id.rawValue).")
        case .outOfBounds:
            String(localized: "Outside the map.")
        case .water:
            String(localized: "Cannot build on water.")
        case .tooSteep(let slope):
            String(localized: "Too steep (\(percent(slope / 100)) slope).")
        case .occupied:
            String(localized: "This space is already taken.")
        case .insufficientFunds(let cost):
            String(localized: "Not enough money: \(cost) thalers needed.")
        case .missingResource(let biome):
            String(localized: "No \(name(of: biome)) nearby.")
        }
    }

    /// Text for an event, or `nil` if the event should not be announced.
    static func message(for event: SimulationEvent, catalog: GameCatalog) -> String? {
        switch event {
        case .settlementFounded(let population):
            String(localized: "A new settlement with \(population) residents was founded.")
        case .buildingPlaced(let type, let cost):
            String(localized: "\(buildingName(type, in: catalog)) built for \(cost) thalers.")
        case .buildingDemolished(let type, let refund):
            String(localized: "\(buildingName(type, in: catalog)) demolished, \(refund) thalers refunded.")
        case .placementRejected(let error):
            message(for: error, catalog: catalog)
        case .residentLeft:
            String(localized: "A resident left because of hunger.")
        case .yearClosed(let year, let taxes, let upkeep):
            String(localized: "Year \(year): \(taxes) thalers taxes, \(upkeep) thalers upkeep.")
        }
    }

    // MARK: - Status

    static func status(of building: Building) -> (text: String, tone: StatusTone) {
        switch building.status {
        case .working:
            (String(localized: "Working"), .good)
        case .idle:
            (String(localized: "Ready"), .neutral)
        case .missingInput:
            (String(localized: "Waiting for inputs"), .warning)
        case .outputFull:
            (String(localized: "Output full – carriers cannot keep up"), .warning)
        case .noWorkers:
            (String(localized: "No workers – build more houses"), .problem)
        case .noResources:
            (String(localized: "No resources in reach"), .problem)
        case .storing:
            (String(localized: "Storehouse"), .neutral)
        case .housing:
            housingStatus(of: building)
        }
    }

    private static func housingStatus(of house: Building) -> (text: String, tone: StatusTone) {
        if house.residents == 0 {
            return (String(localized: "Empty – waiting for food"), .problem)
        }
        if house.supplyRatio >= 0.9 {
            return (String(localized: "Well supplied"), .good)
        }
        if house.supplyRatio >= 0.5 {
            return (String(localized: "Barely supplied"), .warning)
        }
        return (String(localized: "Hungry"), .problem)
    }

    // MARK: - Build menu

    static func summary(of definition: BuildingDefinition, catalog: GameCatalog) -> String {
        func list(_ amounts: [GoodAmount]) -> String {
            amounts.map { "\($0.amount) \(goodName($0.good, in: catalog))" }.formatted(.list(type: .and))
        }
        var parts: [String] = []
        if !definition.inputs.isEmpty {
            parts.append(String(localized: "Needs \(list(definition.inputs))"))
        }
        if !definition.outputs.isEmpty {
            parts.append(String(localized: "Produces \(list(definition.outputs)) in \(Int(definition.cycleDays)) days"))
        }
        if definition.workers > 0 {
            parts.append(String(localized: "\(definition.workers) workers"))
        }
        if let resource = definition.resource {
            parts.append(String(localized: "Needs \(name(of: resource.biome)) nearby"))
        }
        if definition.maxResidents > 0 {
            parts.append(String(localized: "Up to \(definition.maxResidents) residents"))
        }
        return parts.joined(separator: " · ")
    }
}
