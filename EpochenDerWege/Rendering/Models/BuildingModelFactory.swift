import GameDomain
import RealityKit
import simd

/// A placed building model and the parts the renderer animates or decorates.
struct BuildingModel {
    let root: Entity
    /// Height above ground where the status marker floats.
    let markerHeight: Float
    /// Part that spins while the building works, e.g. the sails of a mill.
    let rotor: Entity?
}

/// Creates building models (factory + prototype pattern).
///
/// Each building type is assembled once from primitives into a template. Placing a
/// building clones the template, which shares all meshes and materials with it.
/// The origin of a model is the centre of its cell at ground level; a stone plinth
/// reaches into the ground so buildings on slopes never float.
final class BuildingModelFactory {
    static let rotorName = "rotor"

    private var templates: [BuildingTypeID: (entity: Entity, markerHeight: Float)] = [:]

    func makeModel(for definition: BuildingDefinition) -> BuildingModel {
        let template: (entity: Entity, markerHeight: Float)
        if let cached = templates[definition.id] {
            template = cached
        } else {
            template = Self.build(definition)
            templates[definition.id] = template
        }
        let root = template.entity.clone(recursive: true)
        return BuildingModel(
            root: root,
            markerHeight: template.markerHeight,
            rotor: root.findEntity(named: Self.rotorName)
        )
    }

    // MARK: - Blueprints

    private typealias P = ModelKit.Palette

    private static func build(_ definition: BuildingDefinition) -> (entity: Entity, markerHeight: Float) {
        switch definition.id.rawValue {
        case "house": return house()
        case "storehouse": return storehouse()
        case "woodcutter": return woodcutter()
        case "quarry": return quarry()
        case "grainFarm": return grainFarm()
        case "mill": return mill()
        case "bakery": return bakery()
        case "fishersHut": return fishersHut()
        default: return generic(definition)
        }
    }

    /// Plinth from below ground up to `top`.
    private static func plinth(_ size: SIMD2<Float>, top: Float = 0.4, offset: SIMD2<Float> = .zero) -> ModelEntity {
        ModelKit.box(SIMD3<Float>(size.x, top + 2, size.y), P.stone, at: SIMD3<Float>(offset.x, (top - 2) / 2, offset.y))
    }

    /// Walls with a gable roof, door and windows on the front (+z) side.
    private static func cottage(
        width: Float, depth: Float, wallHeight: Float, roofHeight: Float,
        wall: GameColor, roof: GameColor, base: Float = 0.4, at offset: SIMD2<Float> = .zero, windows: Bool = true
    ) -> Entity {
        let cottage = Entity()
        cottage.position = SIMD3<Float>(offset.x, 0, offset.y)
        cottage.addChild(ModelKit.box(SIMD3<Float>(width, wallHeight, depth), wall, at: SIMD3<Float>(0, base + wallHeight / 2, 0)))
        cottage.addChild(ModelKit.gableRoof(
            width: width + 0.5, depth: depth + 0.6, height: roofHeight,
            roof: roof, gable: wall, baseY: base + wallHeight
        ))
        let front = depth / 2 + 0.03
        cottage.addChild(ModelKit.box(SIMD3<Float>(0.9, 1.6, 0.08), P.darkWood, at: SIMD3<Float>(0, base + 0.8, front)))
        if windows && width > 3 {
            for x in [-width / 2 + 0.9, width / 2 - 0.9] {
                cottage.addChild(ModelKit.box(SIMD3<Float>(0.7, 0.7, 0.08), P.window, at: SIMD3<Float>(x, base + wallHeight * 0.62, front)))
            }
        }
        return cottage
    }

    private static func house() -> (Entity, Float) {
        let root = Entity()
        root.addChild(plinth(SIMD2(5.6, 4.6)))
        root.addChild(cottage(width: 5, depth: 4, wallHeight: 3, roofHeight: 2.2, wall: P.plaster, roof: P.roofTiles))
        root.addChild(ModelKit.box(SIMD3<Float>(0.6, 1.8, 0.6), P.darkStone, at: SIMD3<Float>(1.5, 4.9, -0.8)))
        return (root, 7.5)
    }

    private static func storehouse() -> (Entity, Float) {
        let root = Entity()
        root.addChild(plinth(SIMD2(7.6, 6.4)))
        root.addChild(cottage(width: 7, depth: 5.4, wallHeight: 3.4, roofHeight: 2.8, wall: P.timber, roof: P.thatch, windows: false))
        root.addChild(ModelKit.box(SIMD3<Float>(2.4, 2.6, 0.1), P.darkWood, at: SIMD3<Float>(0, 1.7, 2.75)))
        for (index, x) in [Float(-2.6), -1.7, 2.2].enumerated() {
            root.addChild(ModelKit.box(SIMD3<Float>(0.8, 0.8, 0.8), P.timber.darkened(by: 0.15 * Double(index % 2)), at: SIMD3<Float>(x, 0.8, 3.4), yaw: 0.3 * Float(index)))
        }
        root.addChild(ModelKit.cylinder(height: 1, radius: 0.4, P.darkWood, at: SIMD3<Float>(1.4, 0.9, 3.4)))
        return (root, 8.5)
    }

    private static func woodcutter() -> (Entity, Float) {
        let root = Entity()
        root.addChild(plinth(SIMD2(4.4, 3.8), offset: SIMD2(-1, -0.8)))
        root.addChild(cottage(width: 4, depth: 3.4, wallHeight: 2.4, roofHeight: 1.8, wall: P.timber, roof: P.thatch, at: SIMD2(-1, -0.8)))
        // Log pile.
        for row in 0..<3 {
            for column in 0..<(3 - row) {
                let x = 2.2 + Float(column) * 0.62 + Float(row) * 0.31
                root.addChild(ModelKit.log(length: 3.2, radius: 0.3, P.timber, at: SIMD3<Float>(x, 0.3 + Float(row) * 0.55, 0.6), yaw: .pi / 2))
            }
        }
        root.addChild(ModelKit.cylinder(height: 0.6, radius: 0.45, P.timber.darkened(by: 0.2), at: SIMD3<Float>(1.2, 0.3, 2.6)))
        return (root, 6)
    }

    private static func quarry() -> (Entity, Float) {
        let root = Entity()
        root.addChild(plinth(SIMD2(3.8, 3.4), offset: SIMD2(-1.6, -1.2)))
        root.addChild(cottage(width: 3.4, depth: 3, wallHeight: 2.4, roofHeight: 1.6, wall: P.stone, roof: P.roofTiles, at: SIMD2(-1.6, -1.2), windows: false))
        let blocks: [(SIMD3<Float>, SIMD3<Float>, Float)] = [
            (SIMD3(1.4, 1.0, 1.2), SIMD3(1.8, 0.5, 1.6), 0.2),
            (SIMD3(1.2, 0.9, 1.0), SIMD3(2.4, 0.45, -0.4), -0.4),
            (SIMD3(1.0, 0.8, 1.0), SIMD3(1.9, 1.35, 1.5), 0.6),
            (SIMD3(0.9, 0.7, 0.9), SIMD3(0.2, 0.35, 2.4), 0.1),
        ]
        for (size, position, yaw) in blocks {
            root.addChild(ModelKit.box(size, P.darkStone, at: position, yaw: yaw))
        }
        return (root, 6)
    }

    private static func grainFarm() -> (Entity, Float) {
        let root = Entity()
        root.addChild(plinth(SIMD2(3.6, 3.2), offset: SIMD2(-1.9, -1.9)))
        root.addChild(cottage(width: 3.2, depth: 2.8, wallHeight: 2.4, roofHeight: 1.8, wall: P.plaster, roof: P.thatch, at: SIMD2(-1.9, -1.9), windows: false))
        // Three fields with furrows.
        for center in [SIMD2<Float>(1.9, -1.9), SIMD2<Float>(1.9, 1.9), SIMD2<Float>(-1.9, 1.9)] {
            root.addChild(ModelKit.box(SIMD3<Float>(3.4, 0.3, 3.4), P.field, at: SIMD3<Float>(center.x, 0.1, center.y), cornerRadius: 0.05))
            for row in -1...1 {
                root.addChild(ModelKit.box(SIMD3<Float>(3.2, 0.1, 0.25), P.furrow, at: SIMD3<Float>(center.x, 0.3, center.y + Float(row) * 1.0), cornerRadius: 0))
            }
        }
        return (root, 6)
    }

    private static func mill() -> (Entity, Float) {
        let root = Entity()
        root.addChild(plinth(SIMD2(4.4, 4.4)))
        root.addChild(ModelKit.cylinder(height: 6, radius: 1.9, P.plaster, at: SIMD3<Float>(0, 3.4, 0)))
        root.addChild(ModelKit.cone(height: 2.4, radius: 2.3, P.thatch, at: SIMD3<Float>(0, 7.6, 0)))
        root.addChild(ModelKit.box(SIMD3<Float>(0.9, 1.6, 0.1), P.darkWood, at: SIMD3<Float>(0, 1.2, 1.92)))

        let rotor = Entity()
        rotor.name = rotorName
        rotor.position = SIMD3<Float>(0, 5.6, 2.05)
        rotor.addChild(ModelKit.cylinder(height: 0.5, radius: 0.3, P.darkWood, at: .zero))
        for blade in 0..<4 {
            let arm = Entity()
            arm.orientation = simd_quatf(angle: Float(blade) * .pi / 2, axis: SIMD3<Float>(0, 0, 1))
            arm.addChild(ModelKit.box(SIMD3<Float>(0.18, 3.6, 0.12), P.darkWood, at: SIMD3<Float>(0, 1.9, 0.1)))
            arm.addChild(ModelKit.box(SIMD3<Float>(0.9, 3.0, 0.05), P.sailCloth, at: SIMD3<Float>(0.5, 2.1, 0.14), cornerRadius: 0))
            rotor.addChild(arm)
        }
        root.addChild(rotor)
        return (root, 10.5)
    }

    private static func bakery() -> (Entity, Float) {
        let root = Entity()
        root.addChild(plinth(SIMD2(6.2, 4.8)))
        root.addChild(cottage(width: 4.6, depth: 4, wallHeight: 3, roofHeight: 2, wall: P.plaster, roof: P.roofTiles, at: SIMD2(-0.6, 0)))
        // Bread oven with chimney.
        root.addChild(ModelKit.sphere(radius: 1.2, P.stone, at: SIMD3<Float>(2.3, 0.6, 1), scale: SIMD3<Float>(1, 0.75, 1)))
        root.addChild(ModelKit.box(SIMD3<Float>(0.5, 0.5, 0.1), P.window, at: SIMD3<Float>(2.3, 0.7, 2.15)))
        root.addChild(ModelKit.box(SIMD3<Float>(0.6, 2.6, 0.6), P.darkStone, at: SIMD3<Float>(2.3, 2.2, 0.2)))
        return (root, 7.5)
    }

    private static func fishersHut() -> (Entity, Float) {
        let root = Entity()
        root.addChild(plinth(SIMD2(3.8, 3.4), offset: SIMD2(-1.2, -0.9)))
        root.addChild(cottage(width: 3.4, depth: 3, wallHeight: 2.3, roofHeight: 1.6, wall: P.timber, roof: P.thatch, at: SIMD2(-1.2, -0.9), windows: false))
        // Boat and drying rack.
        root.addChild(ModelKit.box(SIMD3<Float>(1.1, 0.5, 3.2), P.darkWood, at: SIMD3<Float>(2.2, 0.35, 0.6), yaw: 0.25))
        for z in [Float(1.6), 3.0] {
            root.addChild(ModelKit.box(SIMD3<Float>(0.15, 1.8, 0.15), P.darkWood, at: SIMD3<Float>(-2.2, 0.9, z)))
        }
        root.addChild(ModelKit.box(SIMD3<Float>(0.1, 0.1, 1.6), P.darkWood, at: SIMD3<Float>(-2.2, 1.75, 2.3)))
        root.addChild(ModelKit.box(SIMD3<Float>(0.05, 1.0, 1.3), P.sailCloth.darkened(by: 0.25), at: SIMD3<Float>(-2.2, 1.2, 2.3), cornerRadius: 0))
        return (root, 6)
    }

    private static func generic(_ definition: BuildingDefinition) -> (Entity, Float) {
        let root = Entity()
        root.addChild(plinth(SIMD2(5.6, 5.6)))
        root.addChild(cottage(width: 5, depth: 5, wallHeight: 3.4, roofHeight: 2, wall: definition.color, roof: definition.color.darkened(by: 0.45)))
        return (root, 8)
    }
}
