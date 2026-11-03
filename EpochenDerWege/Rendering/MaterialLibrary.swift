import AppKit
import GameDomain
import RealityKit

/// Shared cache of materials and meshes (singleton + flyweight).
///
/// Many entities share the same look: every bakery, every bread carrier. Creating a
/// material or mesh once and reusing it saves memory and lets RealityKit batch draw
/// calls. A singleton fits here because the cache is a pure performance detail with
/// no game state, and it must be shared by all scene layers.
final class MaterialLibrary {
    static let shared = MaterialLibrary()

    private var matteMaterials: [GameColor: SimpleMaterial] = [:]
    private var unlitMaterials: [UnlitKey: UnlitMaterial] = [:]
    private var boxes: [BoxKey: MeshResource] = [:]
    private var spheres: [Float: MeshResource] = [:]

    private init() {}

    /// A rough, non-metallic material, the base look of the low-poly world.
    func matte(_ color: GameColor) -> SimpleMaterial {
        if let cached = matteMaterials[color] { return cached }
        let material = SimpleMaterial(color: NSColor(color), roughness: 0.9, isMetallic: false)
        matteMaterials[color] = material
        return material
    }

    /// A material that ignores lighting, for markers and previews.
    func unlit(_ color: GameColor, opacity: Float = 1) -> UnlitMaterial {
        let key = UnlitKey(color: color, opacity: opacity)
        if let cached = unlitMaterials[key] { return cached }
        var material = UnlitMaterial(color: NSColor(color))
        if opacity < 1 {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        unlitMaterials[key] = material
        return material
    }

    func box(_ size: SIMD3<Float>, cornerRadius: Float = 0.3) -> MeshResource {
        let key = BoxKey(size: size, cornerRadius: cornerRadius)
        if let cached = boxes[key] { return cached }
        let mesh = MeshResource.generateBox(width: size.x, height: size.y, depth: size.z, cornerRadius: cornerRadius)
        boxes[key] = mesh
        return mesh
    }

    func sphere(radius: Float) -> MeshResource {
        if let cached = spheres[radius] { return cached }
        let mesh = MeshResource.generateSphere(radius: radius)
        spheres[radius] = mesh
        return mesh
    }

    private struct UnlitKey: Hashable {
        let color: GameColor
        let opacity: Float
    }

    private struct BoxKey: Hashable {
        let size: SIMD3<Float>
        let cornerRadius: Float
    }
}

extension NSColor {
    convenience init(_ color: GameColor) {
        self.init(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
    }
}

extension GameColor {
    /// Mixes towards black by `fraction` (`0...1`).
    func darkened(by fraction: Double) -> GameColor {
        GameColor(red: red * (1 - fraction), green: green * (1 - fraction), blue: blue * (1 - fraction))
    }

    static let markerGood = GameColor(red: 0.30, green: 0.85, blue: 0.35)
    static let markerWarning = GameColor(red: 1.00, green: 0.80, blue: 0.20)
    static let markerProblem = GameColor(red: 0.95, green: 0.25, blue: 0.20)
    static let carrierEmpty = GameColor(red: 0.35, green: 0.35, blue: 0.35)
    static let selection = GameColor(red: 1, green: 1, blue: 1)
}
