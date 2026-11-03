import Foundation
import GameDomain

/// Provides the game catalog. Hides where the data comes from (bundle, file, network, test fixture).
public protocol GameCatalogRepository: Sendable {
    func loadCatalog() throws -> GameCatalog
}

/// Problems found while loading or validating game data.
public enum GameDataError: Error, Equatable, CustomStringConvertible {
    case resourceNotFound(String)
    case decodingFailed(String)
    case duplicateGood(GoodID)
    case duplicateBuilding(BuildingTypeID)
    case unknownGood(GoodID, referencedBy: String)
    case invalidValue(String)

    public var description: String {
        switch self {
        case .resourceNotFound(let name):
            return "Game data resource '\(name)' was not found."
        case .decodingFailed(let details):
            return "Game data could not be decoded: \(details)"
        case .duplicateGood(let id):
            return "Good '\(id)' is defined more than once."
        case .duplicateBuilding(let id):
            return "Building '\(id)' is defined more than once."
        case .unknownGood(let id, let owner):
            return "'\(owner)' references unknown good '\(id)'."
        case .invalidValue(let details):
            return "Invalid value: \(details)"
        }
    }
}

/// Loads a catalog from a JSON file shipped inside this package.
public struct BundledCatalogRepository: GameCatalogRepository {
    /// Name of the JSON resource without extension.
    public let resourceName: String

    /// The default data set: antiquity.
    public init(resourceName: String = "antiquity") {
        self.resourceName = resourceName
    }

    public func loadCatalog() throws -> GameCatalog {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw GameDataError.resourceNotFound("\(resourceName).json")
        }
        return try JSONCatalogRepository(url: url).loadCatalog()
    }
}

/// Loads a catalog from any JSON file, for example a modded data set.
public struct JSONCatalogRepository: GameCatalogRepository {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func loadCatalog() throws -> GameCatalog {
        let data = try Data(contentsOf: url)
        let catalog: GameCatalog
        do {
            catalog = try JSONDecoder().decode(GameCatalog.self, from: data)
        } catch {
            throw GameDataError.decodingFailed(String(describing: error))
        }
        try CatalogValidator.validate(catalog)
        return catalog
    }
}

/// Checks a catalog for consistency so data mistakes fail fast at load time instead of during play.
public enum CatalogValidator {
    public static func validate(_ catalog: GameCatalog) throws {
        var goods = Set<GoodID>()
        for good in catalog.goods {
            guard goods.insert(good.id).inserted else { throw GameDataError.duplicateGood(good.id) }
        }

        var buildings = Set<BuildingTypeID>()
        for building in catalog.buildings {
            guard buildings.insert(building.id).inserted else { throw GameDataError.duplicateBuilding(building.id) }
            for amount in building.inputs + building.outputs where !goods.contains(amount.good) {
                throw GameDataError.unknownGood(amount.good, referencedBy: building.id.rawValue)
            }
            if building.category == .production && building.cycleDays <= 0 {
                throw GameDataError.invalidValue("'\(building.id)' needs a positive cycle length")
            }
            if building.storagePerGood <= 0 {
                throw GameDataError.invalidValue("'\(building.id)' needs positive storage")
            }
        }

        let rules = catalog.rules
        for good in rules.foodGoods where !goods.contains(good) {
            throw GameDataError.unknownGood(good, referencedBy: "rules.foodGoods")
        }
        for amount in rules.startingStock where !goods.contains(amount.good) {
            throw GameDataError.unknownGood(amount.good, referencedBy: "rules.startingStock")
        }
        if rules.ticksPerDay <= 0 || rules.daysPerYear <= 0 {
            throw GameDataError.invalidValue("day and year lengths must be positive")
        }
        if catalog.firstBuilding(of: .storage) == nil || catalog.firstBuilding(of: .housing) == nil {
            throw GameDataError.invalidValue("a storehouse and a house are required to found a settlement")
        }
    }
}
