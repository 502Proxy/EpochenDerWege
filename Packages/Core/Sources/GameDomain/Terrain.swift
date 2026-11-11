/// Ground type of a map cell.
public enum Biome: String, CaseIterable, Sendable, Codable {
    case water
    case sand
    case grass
    case forest
    case rock
    case snow
}

/// An immutable height field with one biome per cell.
///
/// Heights are stored on the `(size + 1)²` cell corners, biomes on the `size²` cells.
/// Terrain is generated once per world (see `TerrainGenerator` in `GameSimulation`)
/// and never changes, so it can be shared freely between threads.
public struct Terrain: Sendable, Codable {
    /// Number of cells along each side of the map.
    public let size: Int
    /// Edge length of one cell in metres.
    public let cellSize: Double
    /// Height of the water surface in metres.
    public let seaLevel: Double

    private let heights: [Double]
    private let biomes: [Biome]
    /// Natural resources per cell, row-major; empty when the map has none.
    private let deposits: [Deposit?]

    /// Creates terrain from raw data.
    ///
    /// - Parameters:
    ///   - heights: `(size + 1)²` corner heights in row-major order (z outer, x inner).
    ///   - biomes: `size²` cell biomes in row-major order.
    ///   - deposits: `size²` deposits in row-major order, or empty for none.
    public init(size: Int, cellSize: Double, seaLevel: Double, heights: [Double], biomes: [Biome], deposits: [Deposit?] = []) {
        precondition(size > 0, "Terrain needs at least one cell")
        precondition(heights.count == (size + 1) * (size + 1), "Expected one height per cell corner")
        precondition(biomes.count == size * size, "Expected one biome per cell")
        precondition(deposits.isEmpty || deposits.count == size * size, "Expected one deposit entry per cell")
        self.size = size
        self.cellSize = cellSize
        self.seaLevel = seaLevel
        self.heights = heights
        self.biomes = biomes
        self.deposits = deposits
    }

    /// Flat terrain with a single biome. Useful for tests and sandboxes.
    public static func flat(size: Int, cellSize: Double = 8, height: Double = 10, biome: Biome = .grass) -> Terrain {
        Terrain(
            size: size,
            cellSize: cellSize,
            seaLevel: 0,
            heights: Array(repeating: height, count: (size + 1) * (size + 1)),
            biomes: Array(repeating: biome, count: size * size)
        )
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case size, cellSize, seaLevel, heights, biomes, deposits
    }

    /// Biomes and deposits come in large patches and are stored run-length encoded.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let size = try container.decode(Int.self, forKey: .size)
        let heights = try container.decode([Double].self, forKey: .heights)
        let biomes = try container.decode(RunLengthEncoded<Biome>.self, forKey: .biomes)
        let deposits = try container.decode(RunLengthEncoded<Deposit?>.self, forKey: .deposits)
        guard size > 0, heights.count == (size + 1) * (size + 1), biomes.count == size * size,
              deposits.count == 0 || deposits.count == size * size
        else {
            throw DecodingError.dataCorruptedError(forKey: .size, in: container, debugDescription: "Terrain data does not match its size")
        }
        self.init(
            size: size,
            cellSize: try container.decode(Double.self, forKey: .cellSize),
            seaLevel: try container.decode(Double.self, forKey: .seaLevel),
            heights: heights,
            biomes: biomes.values,
            deposits: deposits.values
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(size, forKey: .size)
        try container.encode(cellSize, forKey: .cellSize)
        try container.encode(seaLevel, forKey: .seaLevel)
        try container.encode(heights, forKey: .heights)
        try container.encode(RunLengthEncoded(biomes), forKey: .biomes)
        try container.encode(RunLengthEncoded(deposits), forKey: .deposits)
    }

    /// Returns a copy with the biome of one cell replaced.
    public func replacingBiome(at cell: GridPoint, with biome: Biome) -> Terrain {
        guard contains(cell) else { return self }
        var newBiomes = biomes
        newBiomes[cell.z * size + cell.x] = biome
        return Terrain(size: size, cellSize: cellSize, seaLevel: seaLevel, heights: heights, biomes: newBiomes, deposits: deposits)
    }

    /// Returns a copy with deposits on the given cells.
    public func addingDeposits(_ added: [GridPoint: Deposit]) -> Terrain {
        var newDeposits = deposits.isEmpty ? [Deposit?](repeating: nil, count: size * size) : deposits
        for (cell, deposit) in added where contains(cell) {
            newDeposits[cell.z * size + cell.x] = deposit
        }
        return Terrain(size: size, cellSize: cellSize, seaLevel: seaLevel, heights: heights, biomes: biomes, deposits: newDeposits)
    }

    // MARK: - Queries

    /// Width and depth of the map in metres.
    public var extent: Double { Double(size) * cellSize }

    public func contains(_ cell: GridPoint) -> Bool {
        cell.x >= 0 && cell.z >= 0 && cell.x < size && cell.z < size
    }

    /// Height of a cell corner. Out-of-range indices are clamped to the map edge.
    public func cornerHeight(x: Int, z: Int) -> Double {
        let cx = min(max(x, 0), size)
        let cz = min(max(z, 0), size)
        return heights[cz * (size + 1) + cx]
    }

    /// Biome of a cell. Cells outside the map count as water.
    public func biome(at cell: GridPoint) -> Biome {
        guard contains(cell) else { return .water }
        return biomes[cell.z * size + cell.x]
    }

    /// Natural resource on a cell, if any.
    public func deposit(at cell: GridPoint) -> Deposit? {
        guard !deposits.isEmpty, contains(cell) else { return nil }
        return deposits[cell.z * size + cell.x]
    }

    public func isLand(_ cell: GridPoint) -> Bool {
        biome(at: cell) != .water
    }

    public func center(of cell: GridPoint) -> WorldPoint {
        WorldPoint(x: (Double(cell.x) + 0.5) * cellSize, z: (Double(cell.z) + 0.5) * cellSize)
    }

    /// The cell containing a point, or `nil` outside the map.
    public func cell(containing point: WorldPoint) -> GridPoint? {
        let cell = GridPoint(x: Int((point.x / cellSize).rounded(.down)), z: Int((point.z / cellSize).rounded(.down)))
        return contains(cell) ? cell : nil
    }

    /// Ground height at any point, bilinearly interpolated between cell corners.
    public func height(at point: WorldPoint) -> Double {
        let gx = min(max(point.x / cellSize, 0), Double(size))
        let gz = min(max(point.z / cellSize, 0), Double(size))
        let x0 = min(Int(gx), size - 1)
        let z0 = min(Int(gz), size - 1)
        let tx = gx - Double(x0)
        let tz = gz - Double(z0)
        let top = cornerHeight(x: x0, z: z0) + (cornerHeight(x: x0 + 1, z: z0) - cornerHeight(x: x0, z: z0)) * tx
        let bottom = cornerHeight(x: x0, z: z0 + 1) + (cornerHeight(x: x0 + 1, z: z0 + 1) - cornerHeight(x: x0, z: z0 + 1)) * tx
        return top + (bottom - top) * tz
    }

    /// Ground height, or the water surface where the ground is below sea level.
    public func surfaceHeight(at point: WorldPoint) -> Double {
        max(height(at: point), seaLevel)
    }

    /// Slope of a cell in percent: corner height difference divided by cell size.
    public func slopePercent(at cell: GridPoint) -> Double {
        let corners = [
            cornerHeight(x: cell.x, z: cell.z),
            cornerHeight(x: cell.x + 1, z: cell.z),
            cornerHeight(x: cell.x, z: cell.z + 1),
            cornerHeight(x: cell.x + 1, z: cell.z + 1),
        ]
        return ((corners.max() ?? 0) - (corners.min() ?? 0)) / cellSize * 100
    }
}
