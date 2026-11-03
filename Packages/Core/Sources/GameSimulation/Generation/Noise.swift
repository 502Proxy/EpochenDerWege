/// Small deterministic random number generator (SplitMix64).
///
/// The same seed yields the same sequence on every platform, which keeps maps reproducible.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 2D value noise with fractal layering (fBm), used for height and moisture maps.
struct ValueNoise: Sendable {
    private let values: [Double]
    private let permutation: [Int]

    init(seed: UInt64) {
        var generator = SplitMix64(seed: seed)
        values = (0..<256).map { _ in Double(generator.next() % 1_000_000) / 500_000.0 - 1.0 }
        // Fisher–Yates by hand so the result does not depend on the standard library's shuffle.
        var table = Array(0..<256)
        for i in stride(from: 255, to: 0, by: -1) {
            let j = Int(generator.next() % UInt64(i + 1))
            table.swapAt(i, j)
        }
        permutation = table + table
    }

    /// One octave in `-1...1`.
    func sample(_ x: Double, _ y: Double) -> Double {
        let fx = x.rounded(.down)
        let fy = y.rounded(.down)
        let x0 = Int(fx)
        let y0 = Int(fy)
        let sx = Self.smoothstep(x - fx)
        let sy = Self.smoothstep(y - fy)
        let top = Self.lerp(lattice(x0, y0), lattice(x0 + 1, y0), sx)
        let bottom = Self.lerp(lattice(x0, y0 + 1), lattice(x0 + 1, y0 + 1), sx)
        return Self.lerp(top, bottom, sy)
    }

    /// Several octaves summed and normalised to roughly `-1...1`.
    func fractal(_ x: Double, _ y: Double, octaves: Int, lacunarity: Double = 2, gain: Double = 0.5) -> Double {
        var sum = 0.0
        var amplitude = 1.0
        var frequency = 1.0
        var normaliser = 0.0
        for _ in 0..<octaves {
            sum += sample(x * frequency, y * frequency) * amplitude
            normaliser += amplitude
            amplitude *= gain
            frequency *= lacunarity
        }
        return sum / normaliser
    }

    private func lattice(_ x: Int, _ y: Int) -> Double {
        values[permutation[permutation[x & 255] + (y & 255)]]
    }

    private static func smoothstep(_ t: Double) -> Double {
        t * t * (3 - 2 * t)
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}
