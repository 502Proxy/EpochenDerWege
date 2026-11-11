import GameDomain
import RealityKit
import simd

/// Houses of the neighbouring towns.
///
/// Towns never change, so their houses are built once, on the first update. They
/// reuse the player's house models in a mix of tiers, which makes towns look lived-in
/// and a little richer than a new village.
final class TownLayer: SceneLayer {
    private let parent: Entity
    private let space: SceneSpace
    private let factory = BuildingModelFactory()
    private var isBuilt = false

    init(parent: Entity, space: SceneSpace) {
        self.parent = parent
        self.space = space
    }

    func update(with context: RenderContext) {
        guard !isBuilt else { return }
        isBuilt = true
        let world = context.world
        let tiers = ["house", "citizenHouse", "townhouse"].compactMap { world.catalog.building(BuildingTypeID($0)) }
        guard !tiers.isEmpty else { return }

        for town in world.towns {
            for cell in town.footprint.sorted(by: { ($0.z, $0.x) < ($1.z, $1.x) }) {
                // Leave every other cell free for yards and lanes.
                let hash = (cell.x &* 31 &+ cell.z &* 17) & 7
                guard (cell.x + cell.z) % 2 == 0 || hash == 0 else { continue }
                let tier = tiers[min(tiers.count - 1, hash % 3 == 0 ? 2 : hash % 2)]
                let model = factory.makeModel(for: tier)
                model.root.position = space.local(world.terrain.center(of: cell))
                model.root.orientation = simd_quatf(angle: Float(hash & 3) * .pi / 2, axis: SIMD3<Float>(0, 1, 0))
                parent.addChild(model.root)
            }
        }
    }
}
