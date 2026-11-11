import Foundation
import CoreGraphics
import GameDomain
import simd

/// Paints the ground texture: blended biomes, rock on steep slopes, beaches,
/// surf, snow and fine colour variation.
///
/// Pure computation on value types, so it runs off the main thread. Pixel rows map
/// to the map's z axis and columns to its x axis.
nonisolated struct TerrainTextureBuilder: Sendable {
    let surface: TerrainSurface
    /// Width and height of the texture in pixels.
    let size: Int

    fileprivate typealias RGB = SIMD3<Double>

    fileprivate static let palette: [Biome: RGB] = [
        .water: RGB(0.46, 0.43, 0.32),
        .sand: RGB(0.86, 0.79, 0.57),
        .grass: RGB(0.42, 0.62, 0.27),
        .forest: RGB(0.25, 0.41, 0.18),
        .rock: RGB(0.50, 0.48, 0.45),
        .snow: RGB(0.94, 0.95, 0.97),
    ]
    private static let lushGrass = RGB(0.36, 0.58, 0.22)
    private static let dryGrass = RGB(0.58, 0.64, 0.33)
    private static let cliff = RGB(0.44, 0.42, 0.40)
    private static let beach = RGB(0.88, 0.82, 0.62)
    private static let surf = RGB(0.86, 0.88, 0.86)
    private static let snow = RGB(0.94, 0.95, 0.97)
    fileprivate static let stoneDeposit = RGB(0.60, 0.58, 0.54)
    fileprivate static let vineSlope = RGB(0.36, 0.46, 0.20)

    /// RGBA bytes, row by row.
    ///
    /// Heights, steepness and biome colours are computed once per grid point and then
    /// interpolated per pixel, which keeps a 2048² texture fast to generate.
    func makePixels() -> [UInt8] {
        let terrain = surface.terrain
        let grid = Grid(surface: surface)
        let metresPerPixel = surface.extent / Double(size)
        let cellsPerPixel = metresPerPixel / terrain.cellSize
        let large = DetailNoise(seed: 11)
        let fine = DetailNoise(seed: 23)
        var pixels = [UInt8](repeating: 255, count: size * size * 4)

        for row in 0..<size {
            let z = (Double(row) + 0.5) * metresPerPixel
            let gz = (Double(row) + 0.5) * cellsPerPixel
            for column in 0..<size {
                let x = (Double(column) + 0.5) * metresPerPixel
                let gx = (Double(column) + 0.5) * cellsPerPixel
                var color = grid.biomeColor(gx: gx, gz: gz)

                // Grass varies between lush and dry patches.
                let patch = large.fractal(x / 60, z / 60)
                color = mix(color, patch > 0 ? Self.dryGrass : Self.lushGrass, weight: abs(patch) * 0.35 * grassiness(color))

                let height = grid.height(gx: gx, gz: gz)
                let steepness = smoothstep(0.88, 0.70, grid.upness(gx: gx, gz: gz))

                // Steep slopes show bare rock; beaches near the water line, surf right at it, snow on peaks.
                color = mix(color, Self.cliff, weight: steepness)
                color = mix(color, Self.beach, weight: smoothstep(2.5, 0.6, height) * (1 - steepness))
                color = mix(color, Self.surf, weight: smoothstep(0.6, 0.15, abs(height - surface.seaLevel)) * 0.6)
                color = mix(color, Self.snow, weight: smoothstep(88, 104, height))

                // Fine grain so close-ups do not look flat.
                color *= 0.93 + 0.07 * fine.value(x / 1.7, z / 1.7)

                let index = (row * size + column) * 4
                pixels[index] = Self.byte(color.x)
                pixels[index + 1] = Self.byte(color.y)
                pixels[index + 2] = Self.byte(color.z)
            }
        }
        return pixels
    }

    /// Per-corner heights and steepness and per-cell colours, sampled bilinearly.
    nonisolated private struct Grid {
        let size: Int
        let heights: [Double]
        let upness: [Double]
        let colors: [RGB]

        init(surface: TerrainSurface) {
            let terrain = surface.terrain
            size = terrain.size
            let corners = size + 1
            var heights = [Double](repeating: 0, count: corners * corners)
            var upness = [Double](repeating: 1, count: corners * corners)
            for z in 0...size {
                for x in 0...size {
                    let px = Double(x) * terrain.cellSize
                    let pz = Double(z) * terrain.cellSize
                    heights[z * corners + x] = surface.height(x: px, z: pz)
                    upness[z * corners + x] = Double(surface.normal(x: px, z: pz, step: terrain.cellSize / 2).y)
                }
            }
            var colors = [RGB](repeating: RGB(), count: size * size)
            for z in 0..<size {
                for x in 0..<size {
                    let cell = GridPoint(x: x, z: z)
                    // Deposits show through: gravel for stone, dark green rows for vines.
                    colors[z * size + x] = switch terrain.deposit(at: cell) {
                    case .stone: TerrainTextureBuilder.stoneDeposit
                    case .vines: TerrainTextureBuilder.vineSlope
                    case nil: TerrainTextureBuilder.palette[terrain.biome(at: cell)] ?? RGB(1, 0, 1)
                    }
                }
            }
            self.heights = heights
            self.upness = upness
            self.colors = colors
        }

        func height(gx: Double, gz: Double) -> Double {
            bilinear(heights, width: size + 1, gx: gx, gz: gz)
        }

        func upness(gx: Double, gz: Double) -> Double {
            bilinear(upness, width: size + 1, gx: gx, gz: gz)
        }

        /// Colours belong to cell centres, so the grid is shifted by half a cell.
        func biomeColor(gx: Double, gz: Double) -> RGB {
            let fx = min(max(gx - 0.5, 0), Double(size - 1))
            let fz = min(max(gz - 0.5, 0), Double(size - 1))
            let x0 = min(Int(fx), size - 2)
            let z0 = min(Int(fz), size - 2)
            let tx = smooth(fx - Double(x0))
            let tz = smooth(fz - Double(z0))
            let top = colors[z0 * size + x0] + (colors[z0 * size + x0 + 1] - colors[z0 * size + x0]) * tx
            let bottom = colors[(z0 + 1) * size + x0] + (colors[(z0 + 1) * size + x0 + 1] - colors[(z0 + 1) * size + x0]) * tx
            return top + (bottom - top) * tz
        }

        private func bilinear(_ values: [Double], width: Int, gx: Double, gz: Double) -> Double {
            let fx = min(max(gx, 0), Double(width - 1))
            let fz = min(max(gz, 0), Double(width - 1))
            let x0 = min(Int(fx), width - 2)
            let z0 = min(Int(fz), width - 2)
            let tx = fx - Double(x0)
            let tz = fz - Double(z0)
            let top = values[z0 * width + x0] + (values[z0 * width + x0 + 1] - values[z0 * width + x0]) * tx
            let bottom = values[(z0 + 1) * width + x0] + (values[(z0 + 1) * width + x0 + 1] - values[(z0 + 1) * width + x0]) * tx
            return top + (bottom - top) * tz
        }

        private func smooth(_ t: Double) -> Double {
            t * t * (3 - 2 * t)
        }
    }

    /// How green a colour is, so patch variation only affects grassland.
    private func grassiness(_ color: RGB) -> Double {
        max(0, min(1, (color.y - max(color.x, color.z)) * 6))
    }

    private func mix(_ a: RGB, _ b: RGB, weight: Double) -> RGB {
        let w = min(max(weight, 0), 1)
        return a + (b - a) * w
    }

    private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8(min(max(value, 0), 1) * 255)
    }

    /// Wraps RGBA bytes in a CGImage.
    static func makeImage(pixels: [UInt8], size: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
