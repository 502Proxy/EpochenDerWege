/// A cell on the map grid.
public struct GridPoint: Hashable, Sendable, Codable {
    public var x: Int
    public var z: Int

    public init(x: Int, z: Int) {
        self.x = x
        self.z = z
    }

    /// Returns the cell moved by the given offset.
    public func offset(dx: Int, dz: Int) -> GridPoint {
        GridPoint(x: x + dx, z: z + dz)
    }

    /// Chebyshev distance: the number of king moves between two cells.
    public func ringDistance(to other: GridPoint) -> Int {
        max(abs(other.x - x), abs(other.z - z))
    }
}

/// A position on the ground plane in metres. The map origin is at `(0, 0)`.
public struct WorldPoint: Hashable, Sendable, Codable {
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

    /// Linear interpolation; `t = 0` returns `self`, `t = 1` returns `other`.
    public func interpolated(to other: WorldPoint, fraction t: Double) -> WorldPoint {
        WorldPoint(x: x + (other.x - x) * t, z: z + (other.z - z) * t)
    }
}
