import Foundation
import GameDomain
import RealityKit
import simd

/// Carriers walking across the map.
///
/// Two techniques keep this cheap and smooth:
/// - **Object pool:** carriers come and go every few seconds. Their figures are
///   recycled instead of being created and destroyed each time.
/// - **Interpolation:** the simulation ticks 10 times per second, the screen draws
///   60 or more frames. Positions are blended between the previous and the latest
///   tick so carriers glide instead of jumping.
final class CarrierLayer: SceneLayer {
    /// Figures are drawn larger than life so they stay readable from the default zoom.
    private static let figureScale: Float = 1.7

    private let parent: Entity
    private let space: SceneSpace
    private var active: [CarrierID: Figure] = [:]
    private var pool: [Figure] = []

    init(parent: Entity, space: SceneSpace) {
        self.parent = parent
        self.space = space
    }

    func update(with context: RenderContext) {
        let previous = Dictionary(uniqueKeysWithValues: context.frame.previous.carriers.map { ($0.id, $0) })
        var alive = Set<CarrierID>()

        for carrier in context.world.carriers {
            alive.insert(carrier.id)
            let figure = active[carrier.id] ?? acquire(for: carrier, catalog: context.world.catalog)
            active[carrier.id] = figure

            var position = carrier.position
            if let before = previous[carrier.id], before.phase == carrier.phase {
                position = before.position.interpolated(to: carrier.position, fraction: context.fraction)
            }
            figure.root.position = space.local(position)
            figure.face(towards: carrier.phase == .delivering ? carrier.destination : carrier.origin, from: position)
            figure.setLoaded(carrier.isLoaded)
        }

        for (id, figure) in active where !alive.contains(id) {
            figure.root.isEnabled = false
            pool.append(figure)
            active[id] = nil
        }
    }

    private func acquire(for carrier: Carrier, catalog: GameCatalog) -> Figure {
        let figure = pool.popLast() ?? makeFigure()
        figure.crate.model?.materials = [MaterialLibrary.shared.matte(catalog.good(carrier.cargo.good)?.color ?? .carrierEmpty)]
        figure.setLoaded(true)
        figure.root.isEnabled = true
        return figure
    }

    private func makeFigure() -> Figure {
        typealias P = ModelKit.Palette
        let root = Entity()
        root.scale = SIMD3<Float>(repeating: Self.figureScale)
        root.addChild(ModelKit.cylinder(height: 0.9, radius: 0.28, P.tunic, at: SIMD3<Float>(0, 0.65, 0)))
        root.addChild(ModelKit.sphere(radius: 0.22, P.skin, at: SIMD3<Float>(0, 1.32, 0)))
        let crate = ModelKit.box(SIMD3<Float>(0.5, 0.4, 0.4), .carrierEmpty, at: SIMD3<Float>(0, 0.85, 0.36))
        root.addChild(crate)
        parent.addChild(root)
        return Figure(root: root, crate: crate)
    }

    private final class Figure {
        let root: Entity
        let crate: ModelEntity

        init(root: Entity, crate: ModelEntity) {
            self.root = root
            self.crate = crate
        }

        func setLoaded(_ loaded: Bool) {
            if crate.isEnabled != loaded {
                crate.isEnabled = loaded
            }
        }

        func face(towards target: WorldPoint, from position: WorldPoint) {
            let dx = target.x - position.x
            let dz = target.z - position.z
            guard dx * dx + dz * dz > 0.0001 else { return }
            root.orientation = simd_quatf(angle: Float(atan2(dx, dz)), axis: SIMD3<Float>(0, 1, 0))
        }
    }
}
