import GameDomain
import RealityKit
import simd

/// Builds draped road meshes: a square on every road cell plus a strip to each
/// neighbouring road cell, so connected cells form continuous roads.
struct RoadMeshBuilder {
    /// Half the road width in metres.
    static let halfWidth: Float = 1.9
    /// Height above the terrain, enough to avoid z-fighting on slopes.
    static let lift: Float = 0.25

    let space: SceneSpace

    /// - Parameter material: Material index per cell (lets the preview colour cells differently).
    func makeMesh(cells: Set<GridPoint>, material: (GridPoint) -> UInt32 = { _ in 0 }, name: String) -> MeshResource? {
        let terrain = space.terrain
        var mesh = TriangleMeshBuilder(estimatedTriangles: cells.count * 24)
        let w = Self.halfWidth
        let half = Float(terrain.cellSize) / 2

        for cell in cells {
            let center = terrain.center(of: cell)
            let cx = Float(center.x)
            let cz = Float(center.z)
            let index = material(cell)
            addDrapedQuad(to: &mesh, x0: cx - w, z0: cz - w, x1: cx + w, z1: cz + w, material: index)
            // Strips to the east and south neighbours; west and north are added by those cells.
            if cells.contains(cell.offset(dx: 1, dz: 0)) {
                addDrapedQuad(to: &mesh, x0: cx + w, z0: cz - w, x1: cx + 2 * half - w, z1: cz + w, material: index)
            }
            if cells.contains(cell.offset(dx: 0, dz: 1)) {
                addDrapedQuad(to: &mesh, x0: cx - w, z0: cz + w, x1: cx + w, z1: cz + 2 * half - w, material: index)
            }
        }
        return try? mesh.makeMesh(named: name)
    }

    /// A horizontal rectangle subdivided into a 2 × 2 grid that follows the terrain.
    private func addDrapedQuad(to mesh: inout TriangleMeshBuilder, x0: Float, z0: Float, x1: Float, z1: Float, material: UInt32) {
        let steps = 2
        func point(_ i: Int, _ j: Int) -> SIMD3<Float> {
            let x = x0 + (x1 - x0) * Float(i) / Float(steps)
            let z = z0 + (z1 - z0) * Float(j) / Float(steps)
            return space.local(WorldPoint(x: Double(x), z: Double(z)), lift: Self.lift)
        }
        let up = SIMD3<Float>(0, 1, 0)
        for i in 0..<steps {
            for j in 0..<steps {
                mesh.addTriangle(point(i, j), point(i, j + 1), point(i + 1, j), material: material, outward: up)
                mesh.addTriangle(point(i + 1, j), point(i, j + 1), point(i + 1, j + 1), material: material, outward: up)
            }
        }
    }
}

/// Gravel roads. The mesh is rebuilt only when the set of road cells changes.
final class RoadLayer: SceneLayer {
    static let gravel = GameColor(red: 0.66, green: 0.60, blue: 0.50)

    private let parent: Entity
    private let builder: RoadMeshBuilder
    private var entity: ModelEntity?
    private var shownRoads: Set<GridPoint> = []

    init(parent: Entity, space: SceneSpace) {
        self.parent = parent
        builder = RoadMeshBuilder(space: space)
    }

    func update(with context: RenderContext) {
        let roads = context.world.roads
        guard roads != shownRoads else { return }
        shownRoads = roads
        entity?.removeFromParent()
        entity = nil
        guard let mesh = builder.makeMesh(cells: roads, name: "roads") else { return }
        let model = ModelEntity(mesh: mesh, materials: [MaterialLibrary.shared.matte(Self.gravel)])
        parent.addChild(model)
        entity = model
    }
}

/// Translucent road under construction: green where it can be built, red where it cannot.
final class RoadPreviewLayer: SceneLayer {
    private static let validColor = GameColor(red: 0.35, green: 0.90, blue: 0.40)
    private static let invalidColor = GameColor(red: 0.95, green: 0.30, blue: 0.25)

    private let parent: Entity
    private let builder: RoadMeshBuilder
    private var entity: ModelEntity?
    private var shown: RoadPreview?

    init(parent: Entity, space: SceneSpace) {
        self.parent = parent
        builder = RoadMeshBuilder(space: space)
    }

    func update(with context: RenderContext) {
        guard context.roadPreview != shown else { return }
        shown = context.roadPreview
        entity?.removeFromParent()
        entity = nil
        guard let preview = context.roadPreview else { return }

        let valid = preview.valid
        let cells = Set(preview.cells)
        guard let mesh = builder.makeMesh(cells: cells, material: { valid.contains($0) ? 0 : 1 }, name: "road-preview") else { return }
        let library = MaterialLibrary.shared
        let model = ModelEntity(mesh: mesh, materials: [
            library.unlit(Self.validColor, opacity: 0.55),
            library.unlit(Self.invalidColor, opacity: 0.55),
        ])
        model.position.y = 0.05
        parent.addChild(model)
        entity = model
    }
}
