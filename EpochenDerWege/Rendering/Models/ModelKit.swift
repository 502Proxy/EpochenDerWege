import GameDomain
import RealityKit
import simd

/// Small vocabulary for assembling low-poly models from primitives.
///
/// All meshes and materials come from `MaterialLibrary`, so identical parts share
/// GPU resources no matter how many models use them.
enum ModelKit {
    /// Colour palette of the antiquity era.
    enum Palette {
        static let plaster = GameColor(red: 0.92, green: 0.87, blue: 0.76)
        static let timber = GameColor(red: 0.50, green: 0.34, blue: 0.20)
        static let darkWood = GameColor(red: 0.30, green: 0.20, blue: 0.12)
        static let stone = GameColor(red: 0.62, green: 0.60, blue: 0.56)
        static let darkStone = GameColor(red: 0.45, green: 0.43, blue: 0.40)
        static let roofTiles = GameColor(red: 0.68, green: 0.30, blue: 0.20)
        static let thatch = GameColor(red: 0.80, green: 0.68, blue: 0.40)
        static let window = GameColor(red: 0.22, green: 0.27, blue: 0.32)
        static let field = GameColor(red: 0.88, green: 0.76, blue: 0.34)
        static let furrow = GameColor(red: 0.72, green: 0.58, blue: 0.26)
        static let sailCloth = GameColor(red: 0.95, green: 0.93, blue: 0.86)
        static let skin = GameColor(red: 0.90, green: 0.72, blue: 0.58)
        static let tunic = GameColor(red: 0.42, green: 0.36, blue: 0.55)
    }

    /// A box whose centre is at `position`.
    static func box(_ size: SIMD3<Float>, _ color: GameColor, at position: SIMD3<Float>, yaw: Float = 0, cornerRadius: Float = 0.08) -> ModelEntity {
        let entity = ModelEntity(
            mesh: MaterialLibrary.shared.box(size, cornerRadius: min(cornerRadius, size.min() / 2)),
            materials: [MaterialLibrary.shared.matte(color)]
        )
        entity.position = position
        if yaw != 0 {
            entity.orientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        }
        return entity
    }

    /// A vertical cylinder whose centre is at `position`.
    static func cylinder(height: Float, radius: Float, _ color: GameColor, at position: SIMD3<Float>) -> ModelEntity {
        let entity = ModelEntity(
            mesh: MaterialLibrary.shared.cylinder(height: height, radius: radius),
            materials: [MaterialLibrary.shared.matte(color)]
        )
        entity.position = position
        return entity
    }

    /// A cylinder lying along the x axis, e.g. a log.
    static func log(length: Float, radius: Float, _ color: GameColor, at position: SIMD3<Float>, yaw: Float = 0) -> ModelEntity {
        let entity = cylinder(height: length, radius: radius, color, at: position)
        entity.orientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)) * simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
        return entity
    }

    /// A cone standing on its base; `position` is the centre of the cone's bounding box.
    static func cone(height: Float, radius: Float, _ color: GameColor, at position: SIMD3<Float>) -> ModelEntity {
        let entity = ModelEntity(
            mesh: MaterialLibrary.shared.cone(height: height, radius: radius),
            materials: [MaterialLibrary.shared.matte(color)]
        )
        entity.position = position
        return entity
    }

    static func sphere(radius: Float, _ color: GameColor, at position: SIMD3<Float>, scale: SIMD3<Float> = .one) -> ModelEntity {
        let entity = ModelEntity(
            mesh: MaterialLibrary.shared.sphere(radius: radius),
            materials: [MaterialLibrary.shared.matte(color)]
        )
        entity.position = position
        entity.scale = scale
        return entity
    }

    /// A gable roof with the ridge along x. `baseY` is the eave height.
    ///
    /// The two sloped faces use `roof`, the triangular gable ends use `gable`.
    static func gableRoof(width: Float, depth: Float, height: Float, roof: GameColor, gable: GameColor, baseY: Float) -> ModelEntity {
        let entity = ModelEntity(
            mesh: MaterialLibrary.shared.gableRoof(width: width, depth: depth, height: height),
            materials: [MaterialLibrary.shared.matte(roof), MaterialLibrary.shared.matte(gable)]
        )
        entity.position = SIMD3<Float>(0, baseY, 0)
        return entity
    }

    /// Builds the gable roof mesh. Material 0: slopes and soffit, material 1: gable ends.
    static func makeGableRoofMesh(width: Float, depth: Float, height: Float) throws -> MeshResource? {
        let w = width / 2
        let d = depth / 2
        let frontLeft = SIMD3<Float>(-w, 0, d)
        let frontRight = SIMD3<Float>(w, 0, d)
        let backLeft = SIMD3<Float>(-w, 0, -d)
        let backRight = SIMD3<Float>(w, 0, -d)
        let ridgeLeft = SIMD3<Float>(-w, height, 0)
        let ridgeRight = SIMD3<Float>(w, height, 0)

        var mesh = TriangleMeshBuilder(estimatedTriangles: 8)
        let front = SIMD3<Float>(0, 1, 1)
        let back = SIMD3<Float>(0, 1, -1)
        mesh.addTriangle(frontLeft, frontRight, ridgeRight, material: 0, outward: front)
        mesh.addTriangle(frontLeft, ridgeRight, ridgeLeft, material: 0, outward: front)
        mesh.addTriangle(backLeft, ridgeRight, backRight, material: 0, outward: back)
        mesh.addTriangle(backLeft, ridgeLeft, ridgeRight, material: 0, outward: back)
        mesh.addTriangle(frontLeft, ridgeLeft, backLeft, material: 1, outward: SIMD3<Float>(-1, 0, 0))
        mesh.addTriangle(frontRight, backRight, ridgeRight, material: 1, outward: SIMD3<Float>(1, 0, 0))
        mesh.addTriangle(frontLeft, backLeft, backRight, material: 0, outward: SIMD3<Float>(0, -1, 0))
        mesh.addTriangle(frontLeft, backRight, frontRight, material: 0, outward: SIMD3<Float>(0, -1, 0))
        return try mesh.makeMesh(named: "gable-roof")
    }
}
