import GameDomain

/// Generates a low-poly landscape from a seed.
///
/// The parameters were tuned with a reference implementation: seed 2026 yields about
/// 31 % grassland, 23 % forest, 24 % rock and 16 % water on a 128 × 128 map.
public struct TerrainGenerator: Sendable {
    public var seed: UInt64
    public var size: Int
    public var cellSize: Double

    public init(seed: UInt64, size: Int = 128, cellSize: Double = 8) {
        self.seed = seed
        self.size = size
        self.cellSize = cellSize
    }

    public func generate() -> Terrain {
        let elevation = ValueNoise(seed: seed)
        let mountains = ValueNoise(seed: seed &+ 0x51ED_2701)
        let moisture = ValueNoise(seed: seed &+ 0xA5A5_1234)

        let corners = size + 1
        var heights = [Double](repeating: 0, count: corners * corners)
        for z in 0..<corners {
            for x in 0..<corners {
                let u = Double(x) / Double(size)
                let v = Double(z) / Double(size)
                let base = elevation.fractal(u * 3, v * 3, octaves: 4)
                let mask = mountains.fractal(u * 2 + 17, v * 2 + 31, octaves: 4)
                let mountain = max(0, mask - 0.22) / 0.78
                heights[z * corners + x] = base * 36 + 10 + mountain * 300
            }
        }

        var biomes = [Biome](repeating: .grass, count: size * size)
        for z in 0..<size {
            for x in 0..<size {
                let cornerHeights = [
                    heights[z * corners + x], heights[z * corners + x + 1],
                    heights[(z + 1) * corners + x], heights[(z + 1) * corners + x + 1],
                ]
                let average = cornerHeights.reduce(0, +) / 4
                let slope = ((cornerHeights.max() ?? 0) - (cornerHeights.min() ?? 0)) / cellSize * 100
                let wetness = moisture.fractal(Double(x) / Double(size) * 6, Double(z) / Double(size) * 6, octaves: 3)
                biomes[z * size + x] = Self.biome(height: average, slope: slope, wetness: wetness)
            }
        }

        return Terrain(size: size, cellSize: cellSize, seaLevel: 0, heights: heights, biomes: biomes)
    }

    static func biome(height: Double, slope: Double, wetness: Double) -> Biome {
        if height < 0 { return .water }
        if height < 2 { return .sand }
        if height > 100 { return .snow }
        if height > 45 || slope > 60 { return .rock }
        if wetness > 0.05 { return .forest }
        return .grass
    }
}
