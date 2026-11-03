import GameDomain
import RealityKit
import simd

/// Gravel roads. The mesh is rebuilt only when the set of road cells changes.
final class RoadLayer: SceneLayer {
    static let gravel = GameColor(red: 0.66, green: 0.60, blue: 0.50)

    private let parent: Entity
    private let builder: GroundOverlayBuilder
    private var entity: ModelEntity?
    private var shownRoads: Set<GridPoint> = []

    init(parent: Entity, space: SceneSpace) {
        self.parent = parent
        builder = GroundOverlayBuilder(space: space)
    }

    func update(with context: RenderContext) {
        let roads = context.world.roads
        guard roads != shownRoads else { return }
        shownRoads = roads
        entity?.removeFromParent()
        entity = nil
        guard let mesh = builder.makeRoadMesh(cells: roads, name: "roads") else { return }
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
        let cells = Set(preview.cells)
        guard let mesh = builder.makeRoadMesh(cells: cells, lift: GroundOverlayBuilder.roadLift + 0.05, material: { valid.contains($0) ? 0 : 1 }, name: "road-preview") else { return }
        let library = MaterialLibrary.shared
        let model = ModelEntity(mesh: mesh, materials: [
            library.unlit(Self.validColor, opacity: 0.55),
            library.unlit(Self.invalidColor, opacity: 0.55),
        ])
        parent.addChild(model)
        entity = model
    }
}
