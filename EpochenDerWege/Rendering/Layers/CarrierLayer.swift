import GameDomain
import RealityKit

/// Carriers walking across the map.
///
/// Two techniques keep this cheap and smooth:
/// - **Object pool:** carriers come and go every few seconds. Their entities are
///   recycled instead of being created and destroyed each time.
/// - **Interpolation:** the simulation ticks 10 times per second, the screen draws
///   60 or more frames. Positions are blended between the previous and the latest
///   tick so carriers glide instead of jumping.
final class CarrierLayer: SceneLayer {
    private static let radius: Float = 1.3
    private static let hoverHeight: Float = 1.5

    private let parent: Entity
    private let space: SceneSpace
    private var active: [CarrierID: Entry] = [:]
    private var pool: [ModelEntity] = []

    init(parent: Entity, space: SceneSpace) {
        self.parent = parent
        self.space = space
    }

    func update(with context: RenderContext) {
        let previous = Dictionary(uniqueKeysWithValues: context.frame.previous.carriers.map { ($0.id, $0) })
        var alive = Set<CarrierID>()

        for carrier in context.world.carriers {
            alive.insert(carrier.id)
            let entry = active[carrier.id] ?? acquire(for: carrier, catalog: context.world.catalog)
            active[carrier.id] = entry

            var position = carrier.position
            if let before = previous[carrier.id], before.phase == carrier.phase {
                position = before.position.interpolated(to: carrier.position, fraction: context.fraction)
            }
            entry.entity.position = space.local(position, lift: Self.hoverHeight)

            if !carrier.isLoaded && entry.isLoaded {
                entry.isLoaded = false
                entry.entity.model?.materials = [MaterialLibrary.shared.matte(.carrierEmpty)]
                entry.entity.scale = SIMD3<Float>(repeating: 0.7)
            }
        }

        for (id, entry) in active where !alive.contains(id) {
            release(entry.entity)
            active[id] = nil
        }
    }

    private func acquire(for carrier: Carrier, catalog: GameCatalog) -> Entry {
        let color = catalog.good(carrier.cargo.good)?.color ?? .carrierEmpty
        let entity = pool.popLast() ?? ModelEntity(mesh: MaterialLibrary.shared.sphere(radius: Self.radius), materials: [])
        entity.model?.materials = [MaterialLibrary.shared.matte(color)]
        entity.scale = SIMD3<Float>(repeating: 1)
        entity.isEnabled = true
        if entity.parent == nil {
            parent.addChild(entity)
        }
        return Entry(entity: entity, isLoaded: carrier.isLoaded)
    }

    private func release(_ entity: ModelEntity) {
        entity.isEnabled = false
        pool.append(entity)
    }

    private final class Entry {
        let entity: ModelEntity
        var isLoaded: Bool

        init(entity: ModelEntity, isLoaded: Bool) {
            self.entity = entity
            self.isLoaded = isLoaded
        }
    }
}
