import GameDomain
import RealityKit

/// Highlights the selected building with a flat plate.
final class SelectionLayer: SceneLayer {
    private let space: SceneSpace
    private let plate: ModelEntity

    init(parent: Entity, space: SceneSpace) {
        self.space = space
        plate = ModelEntity(
            mesh: MaterialLibrary.shared.box(SIMD3<Float>(11, 0.4, 11), cornerRadius: 0.2),
            materials: [MaterialLibrary.shared.unlit(.selection, opacity: 0.55)]
        )
        plate.isEnabled = false
        parent.addChild(plate)
    }

    func update(with context: RenderContext) {
        guard let id = context.selectedBuildingID, let building = context.world.building(id) else {
            plate.isEnabled = false
            return
        }
        plate.position = space.local(building.center, lift: 0.3)
        plate.isEnabled = true
    }
}

/// Translucent ghost of the building about to be placed: green if allowed, red if not.
final class PlacementPreviewLayer: SceneLayer {
    private static let validColor = GameColor(red: 0.35, green: 0.90, blue: 0.40)
    private static let invalidColor = GameColor(red: 0.95, green: 0.30, blue: 0.25)

    private let space: SceneSpace
    private let ghost = ModelEntity()
    private var shownKey: Key?

    private struct Key: Equatable {
        let category: BuildingCategory
        let isValid: Bool
    }

    init(parent: Entity, space: SceneSpace) {
        self.space = space
        ghost.isEnabled = false
        parent.addChild(ghost)
    }

    func update(with context: RenderContext) {
        guard let preview = context.preview else {
            ghost.isEnabled = false
            return
        }
        let size = BuildingLayer.previewSize(of: preview.definition.category)
        let key = Key(category: preview.definition.category, isValid: preview.isValid)
        if key != shownKey {
            shownKey = key
            let color = preview.isValid ? Self.validColor : Self.invalidColor
            ghost.model = ModelComponent(
                mesh: MaterialLibrary.shared.box(size),
                materials: [MaterialLibrary.shared.unlit(color, opacity: 0.45)]
            )
        }
        ghost.position = space.local(space.terrain.center(of: preview.cell), lift: size.y / 2)
        ghost.isEnabled = true
    }
}
