import Foundation

public enum Biome: String, Codable, CaseIterable, Hashable {
    case water
    case sand
    case grass
    case forest
    case rock
    case snow
}

/// Eine Kachel auf der Karte.
public struct GridPoint: Hashable, Codable {
    public var x: Int
    public var z: Int

    public init(x: Int, z: Int) {
        self.x = x
        self.z = z
    }
}

/// Ein Punkt in Weltkoordinaten (Meter). Die Karte beginnt bei (0, 0).
public struct WorldPoint: Equatable {
    public var x: Double
    public var z: Double

    public init(x: Double, z: Double) {
        self.x = x
        self.z = z
    }

    public func distance(to other: WorldPoint) -> Double {
        let dx = other.x - x
        let dz = other.z - z
        return (dx * dx + dz * dz).squareRoot()
    }

    public func interpolated(to other: WorldPoint, _ t: Double) -> WorldPoint {
        WorldPoint(x: x + (other.x - x) * t, z: z + (other.z - z) * t)
    }
}

/// Höhenfeld mit Biomen. Höhen liegen auf den Eckpunkten, Biome auf den Kacheln.
public struct Terrain {
    /// Kacheln pro Kartenseite.
    public let size: Int
    /// Kantenlänge einer Kachel in Metern.
    public let cellSize: Double
    public let seaLevel: Double
    /// (size + 1)² Eckpunkt-Höhen in Metern, zeilenweise (z außen, x innen).
    public private(set) var heights: [Double]
    /// size² Biome, zeilenweise.
    public private(set) var biomes: [Biome]

    public var extent: Double { Double(size) * cellSize }

    /// Erzeugt eine Karte aus einem Seed. Gleicher Seed ergibt dieselbe Karte.
    public init(seed: UInt64, size: Int = 128, cellSize: Double = 8) {
        self.size = size
        self.cellSize = cellSize
        self.seaLevel = 0

        let elevation = ValueNoise(seed: seed)
        let mountains = ValueNoise(seed: seed &+ 0x51ED_2701)
        let moisture = ValueNoise(seed: seed &+ 0xA5A5_1234)

        // Werte mit einem Python-Nachbau abgestimmt: Seed 2026 ergibt
        // ca. 31 % Grasland, 23 % Wald, 24 % Fels, 16 % Wasser.
        let n = size + 1
        var h = [Double](repeating: 0, count: n * n)
        for z in 0..<n {
            for x in 0..<n {
                let u = Double(x) / Double(size)
                let v = Double(z) / Double(size)
                let base = elevation.fbm(u * 3, v * 3, octaves: 4)
                let mask = mountains.fbm(u * 2 + 17, v * 2 + 31, octaves: 4)
                let mountain = max(0, mask - 0.22) / 0.78
                h[z * n + x] = base * 36 + 10 + mountain * 300
            }
        }
        heights = h

        var b = [Biome](repeating: .grass, count: size * size)
        for z in 0..<size {
            for x in 0..<size {
                let corners = [h[z * n + x], h[z * n + x + 1], h[(z + 1) * n + x], h[(z + 1) * n + x + 1]]
                let avg = corners.reduce(0, +) / 4
                let slope = ((corners.max() ?? 0) - (corners.min() ?? 0)) / cellSize * 100
                let wet = moisture.fbm(Double(x) / Double(size) * 6, Double(z) / Double(size) * 6, octaves: 3)
                let biome: Biome
                if avg < 0 {
                    biome = .water
                } else if avg < 2 {
                    biome = .sand
                } else if avg > 100 {
                    biome = .snow
                } else if avg > 45 || slope > 60 {
                    biome = .rock
                } else if wet > 0.05 {
                    biome = .forest
                } else {
                    biome = .grass
                }
                b[z * size + x] = biome
            }
        }
        biomes = b
    }

    /// Flache Karte mit einheitlichem Biom – praktisch für Tests.
    public init(flatSize size: Int, cellSize: Double = 8, height: Double = 10, biome: Biome = .grass) {
        self.size = size
        self.cellSize = cellSize
        self.seaLevel = 0
        heights = [Double](repeating: height, count: (size + 1) * (size + 1))
        biomes = [Biome](repeating: biome, count: size * size)
    }

    public mutating func setBiome(_ biome: Biome, at cell: GridPoint) {
        guard contains(cell) else { return }
        biomes[cell.z * size + cell.x] = biome
    }

    public func contains(_ cell: GridPoint) -> Bool {
        cell.x >= 0 && cell.z >= 0 && cell.x < size && cell.z < size
    }

    public func vertexHeight(_ x: Int, _ z: Int) -> Double {
        let cx = min(max(x, 0), size)
        let cz = min(max(z, 0), size)
        return heights[cz * (size + 1) + cx]
    }

    public func biome(at cell: GridPoint) -> Biome {
        guard contains(cell) else { return .water }
        return biomes[cell.z * size + cell.x]
    }

    public func isLand(_ cell: GridPoint) -> Bool {
        contains(cell) && biome(at: cell) != .water
    }

    public func cellCenter(_ cell: GridPoint) -> WorldPoint {
        WorldPoint(x: (Double(cell.x) + 0.5) * cellSize, z: (Double(cell.z) + 0.5) * cellSize)
    }

    public func cell(at point: WorldPoint) -> GridPoint? {
        let c = GridPoint(x: Int((point.x / cellSize).rounded(.down)), z: Int((point.z / cellSize).rounded(.down)))
        return contains(c) ? c : nil
    }

    /// Geländehöhe an einem beliebigen Punkt (bilinear interpoliert).
    public func height(at point: WorldPoint) -> Double {
        let gx = min(max(point.x / cellSize, 0), Double(size))
        let gz = min(max(point.z / cellSize, 0), Double(size))
        let x0 = min(Int(gx), size - 1)
        let z0 = min(Int(gz), size - 1)
        let tx = gx - Double(x0)
        let tz = gz - Double(z0)
        let a = vertexHeight(x0, z0)
        let b = vertexHeight(x0 + 1, z0)
        let c = vertexHeight(x0, z0 + 1)
        let d = vertexHeight(x0 + 1, z0 + 1)
        let top = a + (b - a) * tx
        let bottom = c + (d - c) * tx
        return top + (bottom - top) * tz
    }

    /// Steigung einer Kachel in Prozent (Höhenunterschied der Ecken / Kantenlänge).
    public func slopePercent(at cell: GridPoint) -> Double {
        let corners = [
            vertexHeight(cell.x, cell.z), vertexHeight(cell.x + 1, cell.z),
            vertexHeight(cell.x, cell.z + 1), vertexHeight(cell.x + 1, cell.z + 1),
        ]
        return ((corners.max() ?? 0) - (corners.min() ?? 0)) / cellSize * 100
    }
}
