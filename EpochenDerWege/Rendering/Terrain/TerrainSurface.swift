import GameDomain
import simd

/// The visible ground: a smooth surface through the simulation's corner heights.
///
/// The simulation works on an 8 m grid and interpolates heights bilinearly, which
/// looks faceted up close. The renderer uses Catmull-Rom interpolation instead, so
/// hills are rounded. Everything drawn on the ground (buildings, roads, trees) and
/// mouse picking use this surface, so objects sit exactly on what the player sees.
nonisolated struct TerrainSurface: Sendable {
    let terrain: Terrain

    var extent: Double { terrain.extent }
    var seaLevel: Double { terrain.seaLevel }

    /// Smooth ground height in metres.
    func height(x: Double, z: Double) -> Double {
        let size = terrain.size
        let gx = min(max(x / terrain.cellSize, 0), Double(size))
        let gz = min(max(z / terrain.cellSize, 0), Double(size))
        let ix = min(Int(gx), size - 1)
        let iz = min(Int(gz), size - 1)
        let tx = gx - Double(ix)
        let tz = gz - Double(iz)

        var rows = SIMD4<Double>()
        for j in 0..<4 {
            let z = iz - 1 + j
            let row = SIMD4<Double>(
                terrain.cornerHeight(x: ix - 1, z: z),
                terrain.cornerHeight(x: ix, z: z),
                terrain.cornerHeight(x: ix + 1, z: z),
                terrain.cornerHeight(x: ix + 2, z: z)
            )
            rows[j] = Self.catmullRom(row, tx)
        }
        return Self.catmullRom(rows, tz)
    }

    func height(at point: WorldPoint) -> Double {
        height(x: point.x, z: point.z)
    }

    /// Ground height, or the water surface where the ground is below sea level.
    func surfaceHeight(at point: WorldPoint) -> Double {
        max(height(at: point), seaLevel)
    }

    /// Upward surface normal from central differences.
    func normal(x: Double, z: Double, step: Double = 1) -> SIMD3<Float> {
        let dx = height(x: x + step, z: z) - height(x: x - step, z: z)
        let dz = height(x: x, z: z + step) - height(x: x, z: z - step)
        return simd_normalize(SIMD3<Float>(Float(-dx), Float(2 * step), Float(-dz)))
    }

    /// Catmull-Rom spline through four samples, evaluated between the middle two.
    private static func catmullRom(_ p: SIMD4<Double>, _ t: Double) -> Double {
        let t2 = t * t
        let t3 = t2 * t
        return 0.5 * (
            2 * p[1]
                + (-p[0] + p[2]) * t
                + (2 * p[0] - 5 * p[1] + 4 * p[2] - p[3]) * t2
                + (-p[0] + 3 * p[1] - 3 * p[2] + p[3]) * t3
        )
    }
}

/// Cheap, deterministic 2D value noise for visual variation (not used by the simulation).
nonisolated struct DetailNoise: Sendable {
    let seed: UInt32

    func value(_ x: Double, _ z: Double) -> Double {
        let x0 = Int((x).rounded(.down))
        let z0 = Int((z).rounded(.down))
        let tx = x - Double(x0)
        let tz = z - Double(z0)
        let sx = tx * tx * (3 - 2 * tx)
        let sz = tz * tz * (3 - 2 * tz)
        let a = lattice(x0, z0)
        let b = lattice(x0 + 1, z0)
        let c = lattice(x0, z0 + 1)
        let d = lattice(x0 + 1, z0 + 1)
        let top = a + (b - a) * sx
        let bottom = c + (d - c) * sx
        return top + (bottom - top) * sz
    }

    /// Two octaves in roughly `-1...1`.
    func fractal(_ x: Double, _ z: Double) -> Double {
        (value(x, z) * 2 + value(x * 2.7, z * 2.7)) / 3
    }

    private func lattice(_ x: Int, _ z: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ z &* 668_265_263) &+ seed &* 2_246_822_519
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Double(h % 10_000) / 5_000 - 1
    }
}
