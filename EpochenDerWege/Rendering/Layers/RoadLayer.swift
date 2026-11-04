import GameDomain
import RealityKit
import simd

/// Gravel roads and tunnel portals. Rebuilt only when roads or tunnels change.
///
/// Tunnel cells are not drawn on the surface. Where a tunnel meets a surface road
/// (or ends), a stone portal marks the entrance.
final class RoadLayer: SceneLayer {
    static let gravel = GameColor(red: 0.66, green: 0.60, blue: 0.50)
    private static let portalStone = GameColor(red: 0.50, green: 0.48, blue: 0.45)

    private let parent: Entity
    private let space: SceneSpace
    private let builder: GroundOverlayBuilder
    private var entity: Entity?
    private var shown: (roads: Set<GridPoint>, tunnels: Set<GridPoint>)?

    init(parent: Entity, space: SceneSpace) {
        self.parent = parent
        self.space = space
        builder = GroundOverlayBuilder(space: space)
    }

    func update(with context: RenderContext) {
        let roads = context.world.roads
        let tunnels = context.world.tunnels
        if let shown, shown.roads == roads, shown.tunnels == tunnels { return }
        shown = (roads, tunnels)
        entity?.removeFromParent()
        entity = nil

        let root = Entity()
        if let mesh = builder.makeRoadMesh(cells: roads.subtracting(tunnels), name: "roads") {
            root.addChild(ModelEntity(mesh: mesh, materials: [MaterialLibrary.shared.matte(Self.gravel)]))
        }
        for tunnel in tunnels {
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let neighbour = tunnel.offset(dx: dx, dz: dz)
                guard roads.contains(neighbour), !tunnels.contains(neighbour) else { continue }
                root.addChild(makePortal(between: tunnel, and: neighbour))
            }
        }
        parent.addChild(root)
        entity = root
    }

    /// A stone arch on the edge between a tunnel cell and the surface road next to it.
    private func makePortal(between tunnel: GridPoint, and outside: GridPoint) -> Entity {
        let terrain = space.terrain
        let a = terrain.center(of: tunnel)
        let b = terrain.center(of: outside)
        let edge = WorldPoint(x: (a.x + b.x) / 2, z: (a.z + b.z) / 2)
        let portal = Entity()
        portal.position = space.local(edge)
        // Face along the road: the arch spans across it.
        let alongX = tunnel.z == outside.z
        portal.orientation = simd_quatf(angle: alongX ? .pi / 2 : 0, axis: SIMD3<Float>(0, 1, 0))
        let stone = Self.portalStone
        portal.addChild(ModelKit.box(SIMD3<Float>(1.2, 4.5, 1.6), stone, at: SIMD3<Float>(-2.6, 1.6, 0)))
        portal.addChild(ModelKit.box(SIMD3<Float>(1.2, 4.5, 1.6), stone, at: SIMD3<Float>(2.6, 1.6, 0)))
        portal.addChild(ModelKit.box(SIMD3<Float>(6.4, 1.2, 1.8), stone.darkened(by: 0.1), at: SIMD3<Float>(0, 4.2, 0)))
        portal.addChild(ModelKit.box(SIMD3<Float>(4.0, 3.6, 0.2), GameColor(red: 0.08, green: 0.07, blue: 0.06), at: SIMD3<Float>(0, 1.8, 0.4), cornerRadius: 0))
        return portal
    }
}

/// Translucent road under construction: green where it can be built, red where it cannot.
final class RoadPreviewLayer: SceneLayer {
    private static let validColor = GameColor(red: 0.35, green: 0.90, blue: 0.40)
    private static let invalidColor = GameColor(red: 0.95, green: 0.30, blue: 0.25)
    private static let tunnelColor = GameColor(red: 0.60, green: 0.40, blue: 0.95)

    private let parent: Entity
    private let builder: GroundOverlayBuilder
    private var entity: ModelEntity?
    private var shown: RoadPreview?

    init(parent: Entity, space: SceneSpace) {
        self.parent = parent
        builder = GroundOverlayBuilder(space: space)
    }

    func update(with context: RenderContext) {
        guard context.roadPreview != shown else { return }
        shown = context.roadPreview
        entity?.removeFromParent()
        entity = nil
        guard let preview = context.roadPreview else { return }

        let valid = preview.valid
        let tunnels = preview.tunnels
        let cells = Set(preview.cells)
        guard let mesh = builder.makeRoadMesh(cells: cells, lift: GroundOverlayBuilder.roadLift + 0.05, material: { tunnels.contains($0) ? 2 : valid.contains($0) ? 0 : 1 }, name: "road-preview") else { return }
        let library = MaterialLibrary.shared
        let model = ModelEntity(mesh: mesh, materials: [
            library.unlit(Self.validColor, opacity: 0.55),
            library.unlit(Self.invalidColor, opacity: 0.55),
            library.unlit(Self.tunnelColor, opacity: 0.6),
        ])
        parent.addChild(model)
        entity = model
    }
}
