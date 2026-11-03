import Foundation

/// Kleiner, deterministischer Zufallsgenerator (SplitMix64).
/// Gleicher Seed ergibt auf jedem Rechner dieselbe Zahlenfolge – wichtig für reproduzierbare Karten.
public struct SplitMix64: RandomNumberGenerator {
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

/// 2D-Value-Noise mit fraktaler Überlagerung (fBm) für Höhen- und Feuchtigkeitskarten.
struct ValueNoise {
    private let values: [Double]
    private let permutation: [Int]

    init(seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        var vals: [Double] = []
        vals.reserveCapacity(256)
        for _ in 0..<256 {
            vals.append(Double(rng.next() % 1_000_000) / 500_000.0 - 1.0)
        }
        // Fisher-Yates von Hand, damit das Ergebnis nicht von der Standardbibliothek abhängt.
        var perm = Array(0..<256)
        for i in stride(from: 255, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            perm.swapAt(i, j)
        }
        values = vals
        permutation = perm + perm
    }

    private func lattice(_ x: Int, _ y: Int) -> Double {
        values[permutation[permutation[x & 255] + (y & 255)]]
    }

    private static func smooth(_ t: Double) -> Double {
        t * t * (3 - 2 * t)
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    /// Einzelne Oktave, Wertebereich -1...1.
    func sample(_ x: Double, _ y: Double) -> Double {
        let fx = x.rounded(.down)
        let fy = y.rounded(.down)
        let x0 = Int(fx)
        let y0 = Int(fy)
        let sx = ValueNoise.smooth(x - fx)
        let sy = ValueNoise.smooth(y - fy)
        let a = lattice(x0, y0)
        let b = lattice(x0 + 1, y0)
        let c = lattice(x0, y0 + 1)
        let d = lattice(x0 + 1, y0 + 1)
        return ValueNoise.lerp(ValueNoise.lerp(a, b, sx), ValueNoise.lerp(c, d, sx), sy)
    }

    /// Mehrere Oktaven überlagert, normiert auf etwa -1...1.
    func fbm(_ x: Double, _ y: Double, octaves: Int, lacunarity: Double = 2, gain: Double = 0.5) -> Double {
        var sum = 0.0
        var amplitude = 1.0
        var frequency = 1.0
        var norm = 0.0
        for _ in 0..<octaves {
            sum += sample(x * frequency, y * frequency) * amplitude
            norm += amplitude
            amplitude *= gain
            frequency *= lacunarity
        }
        return sum / norm
    }
}
