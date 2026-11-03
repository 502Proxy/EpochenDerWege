import Foundation
import GameDomain
import RealityKit
import simd

/// Ox carts driving their lines.
///
/// Like carriers, vehicles are pooled and interpolated between simulation ticks.
/// A cart shows a crate while it carries goods.
final class VehicleLayer: SceneLayer {
    /// Drawn slightly larger than life so carts stay readable from the default zoom.
    private static let modelScale: Float = 1.3
    /// Larger jumps between two ticks are not interpolated (e.g. after arriving at a stop).
    private static let maximumInterpolatedDistance = 20.0

    private let parent: Entity
    private let space: SceneSpace
    private var active: [VehicleID: Cart] = [:]
    private var pool: [Cart] = []

    init(parent: Entity, space: SceneSpace) {
        self.parent = parent
        self.space = space
    }

    func update(with context: RenderContext) {
        let previous = Dictionary(uniqueKeysWithValues: context.frame.previous.vehicles.map { ($0.id, $0.position) })
        var alive = Set<VehicleID>()

        for vehicle in context.world.vehicles {
            alive.insert(vehicle.id)
            let cart = active[vehicle.id] ?? acquire()
            active[vehicle.id] = cart

            var position = vehicle.position
            if let before = previous[vehicle.id], before.distance(to: position) < Self.maximumInterpolatedDistance {
                position = before.interpolated(to: position, fraction: context.fraction)
                let dx = vehicle.position.x - before.x
                let dz = vehicle.position.z - before.z
                if dx * dx + dz * dz > 0.0001 {
                    cart.root.orientation = simd_quatf(angle: Float(atan2(dx, dz)), axis: SIMD3<Float>(0, 1, 0))
                }
            }
            cart.root.position = space.local(position)
            cart.crate.isEnabled = vehicle.load > 0
        }

        for (id, cart) in active where !alive.contains(id) {
            cart.root.isEnabled = false
            pool.append(cart)
            active[id] = nil
        }
    }

    private func acquire() -> Cart {
        if let cart = pool.popLast() {
            cart.root.isEnabled = true
            return cart
        }
        let cart = Self.makeOxCart()
        cart.root.scale = SIMD3<Float>(repeating: Self.modelScale)
        parent.addChild(cart.root)
        return cart
    }

    private final class Cart {
        let root: Entity
        let crate: Entity

        init(root: Entity, crate: Entity) {
            self.root = root
            self.crate = crate
        }
    }

    /// An ox pulling a two-wheeled cart. The model faces +z.
    private static func makeOxCart() -> Cart {
        typealias P = ModelKit.Palette
        let ox = GameColor(red: 0.45, green: 0.32, blue: 0.22)
        let root = Entity()

        // Cart with two wheels.
        root.addChild(ModelKit.box(SIMD3<Float>(1.5, 0.5, 2.2), P.timber, at: SIMD3<Float>(0, 0.9, -0.6)))
        for x in [Float(-0.85), 0.85] {
            let wheel = ModelKit.cylinder(height: 0.2, radius: 0.55, P.darkWood, at: SIMD3<Float>(x, 0.55, -0.6))
            wheel.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
            root.addChild(wheel)
        }
        root.addChild(ModelKit.box(SIMD3<Float>(0.12, 0.12, 1.6), P.darkWood, at: SIMD3<Float>(0, 0.9, 1.2)))

        // Ox.
        root.addChild(ModelKit.box(SIMD3<Float>(0.9, 0.9, 1.6), ox, at: SIMD3<Float>(0, 1.0, 2.3)))
        root.addChild(ModelKit.box(SIMD3<Float>(0.5, 0.5, 0.6), ox.darkened(by: 0.15), at: SIMD3<Float>(0, 1.35, 3.3)))
        for x in [Float(-0.3), 0.3] {
            for z in [Float(1.8), 2.8] {
                root.addChild(ModelKit.box(SIMD3<Float>(0.2, 0.6, 0.2), ox.darkened(by: 0.2), at: SIMD3<Float>(x, 0.3, z)))
            }
        }

        let crate = ModelKit.box(SIMD3<Float>(1.0, 0.6, 1.2), P.field, at: SIMD3<Float>(0, 1.45, -0.6))
        root.addChild(crate)
        return Cart(root: root, crate: crate)
    }
}
