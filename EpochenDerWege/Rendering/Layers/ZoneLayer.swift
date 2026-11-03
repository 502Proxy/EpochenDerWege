import GameDomain
import RealityKit

/// Zones on the ground: a tinted fill with a solid outline along the zone border,
/// and a bright frame around the area being drawn.
///
/// Fills are skipped under buildings and roads so those stand out on top of the zone.
/// The mesh is rebuilt only when zones, buildings, roads or the preview change.
final class ZoneLayer: SceneLayer {
    private static let previewFrame = GameColor(red: 1, green: 1, blue: 1)
    private static let removal = GameColor(red: 0.95, green: 0.50, blue: 0.15)

    /// Colour per zone kind.
    static func color(of kind: ZoneKind) -> GameColor {
        switch kind {
        case .residential: GameColor(red: 0.30, green: 0.85, blue: 0.35)
        }
    }

    private let parent: Entity
    private let builder: GroundOverlayBuilder
    private var entity: Entity?
    private var shownKey: Key?

    private struct Key: Equatable {
        let zones: [GridPoint: ZoneKind]
        let buildings: [BuildingID]
        let roads: Set<GridPoint>
        let preview: ZonePreview?
    }

    init(parent: Entity, space: SceneSpace) {
        self.parent = parent
        builder = GroundOverlayBuilder(space: space)
    }

    func update(with context: RenderContext) {
        let world = context.world
        let key = Key(zones: world.zones, buildings: world.buildings.map(\.id), roads: world.roads, preview: context.zonePreview)
        guard key != shownKey else { return }
        shownKey = key
        entity?.removeFromParent()
        entity = nil

        var zones = world.zones
        if let preview = context.zonePreview {
            for cell in preview.cells {
                if let kind = preview.kind {
                    if world.terrain.isLand(cell) { zones[cell] = kind }
                } else {
                    zones[cell] = nil
                }
            }
        }

        let library = MaterialLibrary.shared
        let root = Entity()
        // Fills, outlines and the preview are stacked a few centimetres apart so they never flicker.
        for kind in ZoneKind.allCases {
            let cells = Set(zones.filter { $0.value == kind }.keys)
            guard !cells.isEmpty else { continue }
            let color = Self.color(of: kind)
            let free = cells.filter { !world.isOccupied($0) && !world.hasRoad(at: $0) }
            add(builder.fillQuads(cells: free, material: 0), lift: 0, material: library.unlit(color, opacity: 0.38), to: root)
            let outline = builder.outlineQuads(cells: cells, material: 0) { zones[$0] == kind }
            add(outline, lift: 0.03, material: library.unlit(color.darkened(by: 0.25), opacity: 0.95), to: root)
        }

        if let preview = context.zonePreview {
            let isRemoval = preview.kind == nil
            let color = preview.kind.map(Self.color(of:)) ?? Self.removal
            add(builder.fillQuads(cells: preview.cells, material: 0), lift: 0.06, material: library.unlit(color, opacity: 0.3), to: root)
            let frame = builder.outlineQuads(cells: preview.cells, material: 0, width: 1.0) { preview.cells.contains($0) }
            add(frame, lift: 0.09, material: library.unlit(isRemoval ? Self.removal : Self.previewFrame, opacity: 1), to: root)
        }

        parent.addChild(root)
        entity = root
    }

    private func add(_ quads: [GroundQuad], lift: Float, material: any Material, to root: Entity) {
        guard let mesh = builder.makeMesh(quads: quads, lift: GroundOverlayBuilder.zoneLift + lift, name: "zones") else { return }
        root.addChild(ModelEntity(mesh: mesh, materials: [material]))
    }
}
