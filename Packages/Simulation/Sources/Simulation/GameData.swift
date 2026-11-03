import Foundation

/// Globale Spielregeln. Alle Werte kommen aus der JSON-Datei, damit das Balancing ohne Code-Änderung geht.
public struct Rules: Codable, Equatable {
    /// Simulationsschritte pro Spieltag (bei 10 Ticks pro Sekunde = 2 Sekunden pro Tag).
    public var ticksPerDay: Int
    public var daysPerYear: Int
    public var startMoney: Int
    /// Wie weit ein Träger an einem Spieltag läuft.
    public var carrierSpeedMetersPerDay: Double
    /// Wie viele Einheiten ein Träger auf einmal trägt.
    public var carrierCapacity: Int
    /// Maximale Entfernung, über die Träger Waren bringen.
    public var carrierRadiusMeters: Double
    /// Alle wie viele Ticks Träger neue Aufträge annehmen.
    public var dispatchIntervalTicks: Int
    /// Alle wie viele Tage Häuser essen und wachsen oder schrumpfen.
    public var supplyCheckDays: Int
    /// Nahrung pro Bewohner und Versorgungsprüfung.
    public var foodPerResidentPerCheck: Double
    public var taxPerResidentPerYear: Int
    public var maxSlopePercent: Double
    /// Anteil der Baukosten, der beim Abriss zurückkommt.
    public var refundPercent: Int
    /// Waren, die Häuser als Nahrung annehmen, in Reihenfolge der Vorliebe.
    public var foodGoods: [String]
    public var startHouses: Int
    public var startResidentsPerHouse: Int
    public var startStock: [String: Int]
}

public struct GoodDefinition: Codable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var basePrice: Int
    /// RGB-Farbe (0...1) für die Darstellung im Prototyp.
    public var color: [Double]
}

public enum BuildingCategory: String, Codable, Hashable {
    case production
    case storage
    case housing
}

/// Ein Betrieb braucht ein bestimmtes Gelände in seiner Nähe (Wald für Holzfäller, Wasser für Fischer).
public struct ResourceRequirement: Codable, Hashable {
    public var biome: Biome
    /// Suchradius in Kacheln.
    public var radius: Int
    /// Ab so vielen passenden Kacheln arbeitet der Betrieb mit voller Leistung.
    public var idealCount: Int
}

public struct BuildingDefinition: Codable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var category: BuildingCategory
    public var cost: Int
    public var upkeepPerYear: Int
    public var workers: Int
    public var inputs: [String: Int]
    public var outputs: [String: Int]
    public var cycleDays: Double
    /// Lagerplatz pro Ware (Eingang und Ausgang getrennt).
    public var storagePerGood: Int
    /// Wie viele Träger gleichzeitig von hier aus unterwegs sein dürfen.
    public var maxCarriers: Int
    /// Höchstzahl an Bewohnern (nur Häuser).
    public var residents: Int
    public var resource: ResourceRequirement?
    /// RGB-Farbe (0...1) für die Darstellung im Prototyp.
    public var color: [Double]
}

public enum GameDataError: Error {
    case missingFile(String)
}

public struct GameData: Codable {
    public var rules: Rules
    public var goods: [GoodDefinition]
    public var buildings: [BuildingDefinition]

    public init(rules: Rules, goods: [GoodDefinition], buildings: [BuildingDefinition]) {
        self.rules = rules
        self.goods = goods
        self.buildings = buildings
    }

    public func building(_ id: String) -> BuildingDefinition? {
        buildings.first { $0.id == id }
    }

    public func good(_ id: String) -> GoodDefinition? {
        goods.first { $0.id == id }
    }

    public func goodName(_ id: String) -> String {
        good(id)?.name ?? id
    }

    public static func load(from url: URL) throws -> GameData {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GameData.self, from: data)
    }

    /// Lädt die mitgelieferten Daten der Antike.
    public static func loadDefault() throws -> GameData {
        guard let url = Bundle.module.url(forResource: "antike", withExtension: "json") else {
            throw GameDataError.missingFile("antike.json")
        }
        return try load(from: url)
    }
}
