import GameDomain
import RealityKit

/// Tints zoned cells and shows the area being zoned while dragging.
///
/// Only free cells are tinted, so houses and roads stand out on top of the zone.
/// The mesh is rebuilt only when zones, buildings, roads or the preview change.
final class ZoneLayer: SceneLayer {
    private static let residential = GameColor(red: 0.35, green: 0.85, blue: 0.40)
    private static let removal = GameColor(red: 0.95, green: 0.55, blue: 0.20)

    private let parent: Entity
    private let builder: RoadMeshBuilder
    private var entity: ModelEntity?
    private var shownKey: Key?

    private struct Key: Equatable {
        let zones: [GridPoint: ZoneKind]
        let buildings: [BuildingID]
        let roads: Set<GridPoint>
        let preview: ZonePreview?
    }

    init(parent: Entity, space: SceneSpace) {
        self.parent = parent
        builder = RoadMeshBuilder(space: space)
    }

    func update(with context: RenderContext) {
        let world = context.world
        let key = Key(zones: world.zones, buildings: world.buildings.map(\.id), roads: world.roads, preview: context.zonePreview)
        guard key != shownKey else { return }
        shownKey = key
        entity?.removeFromParent()
        entity = nil

        var tinted = Set(world.zones.keys.filter { !world.isOccupied($0) && !world.hasRoad(at: $0) })
        var removed = Set<GridPoint>()
        if let preview = context.zonePreview {
            if preview.kind == nil {
                removed = preview.cells
                tinted.subtract(preview.cells)
            } else {
                tinted.formUnion(preview.cells.filter { world.terrain.isLand($0) })
            }
        }
        let cells = tinted.union(removed)
        guard let mesh = builder.makeTileMesh(cells: cells, material: { removed.contains($0) ? 1 : 0 }, name: "zones") else { return }
        let library = MaterialLibrary.shared
        let model = ModelEntity(mesh: mesh, materials: [
            library.unlit(Self.residential, opacity: 0.3),
            library.unlit(Self.removal, opacity: 0.4),
        ])
        parent.addChild(model)
        entity = model
    }
}
