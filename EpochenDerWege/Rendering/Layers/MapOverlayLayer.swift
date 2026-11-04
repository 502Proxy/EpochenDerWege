import GameDomain
import GameSimulation
import RealityKit

/// What the map overlay shows.
enum MapOverlay: String, CaseIterable, Hashable {
    case none
    /// Houses by food supply, businesses by efficiency.
    case supply
    /// Cells within carrier range of storehouses and stops.
    case coverage

    var next: MapOverlay {
        let all = Self.allCases
        return all[((all.firstIndex(of: self) ?? 0) + 1) % all.count]
    }
}

/// Colours the ground to show supply or carrier coverage at a glance.
///
/// The mesh is rebuilt only when the overlay or the data it shows changes; values are
/// bucketed so small fluctuations do not cause rebuilds.
final class MapOverlayLayer: SceneLayer {
    /// Red → yellow → green in five steps.
    private static let scale: [GameColor] = [
        GameColor(red: 0.90, green: 0.20, blue: 0.20),
        GameColor(red: 0.95, green: 0.50, blue: 0.20),
        GameColor(red: 0.95, green: 0.85, blue: 0.25),
        GameColor(red: 0.60, green: 0.85, blue: 0.30),
        GameColor(red: 0.25, green: 0.80, blue: 0.35),
    ]
    private static let storageCoverage = GameColor(red: 0.30, green: 0.55, blue: 0.95)
    private static let stopCoverage = GameColor(red: 0.95, green: 0.80, blue: 0.25)

    private let parent: Entity
    private let space: SceneSpace
    private let builder: GroundOverlayBuilder
    private var entity: Entity?
    private var shownKey: Key?

    private struct Key: Equatable {
        let overlay: MapOverlay
        let values: [BuildingID: Int]
    }

    init(parent: Entity, space: SceneSpace) {
        self.parent = parent
        self.space = space
        builder = GroundOverlayBuilder(space: space)
    }

    func update(with context: RenderContext) {
        let world = context.world
        let key = Key(overlay: context.overlay, values: Self.values(for: context.overlay, in: world))
        guard key != shownKey else { return }
        shownKey = key
        entity?.removeFromParent()
        entity = nil

        let root = Entity()
        switch context.overlay {
        case .none:
            return
        case .supply:
            for (bucket, color) in Self.scale.enumerated() {
                let cells = Set(world.buildings.filter { key.values[$0.id] == bucket }.map(\.cell))
                add(builder.fillQuads(cells: cells, material: 0, inset: -1.5), lift: 0.2, color: color, opacity: 0.75, to: root)
            }
        case .coverage:
            add(coverage(of: .storage, in: world), color: Self.storageCoverage, to: root, lift: 0.18)
            add(coverage(of: .stop, in: world), color: Self.stopCoverage, to: root, lift: 0.21)
        }
        parent.addChild(root)
        entity = root
    }

    /// One bucket (0…4) per building that the overlay colours.
    private static func values(for overlay: MapOverlay, in world: WorldState) -> [BuildingID: Int] {
        func bucket(_ fraction: Double) -> Int {
            min(scale.count - 1, max(0, Int(fraction * Double(scale.count - 1) + 0.5)))
        }
        switch overlay {
        case .none:
            return [:]
        case .supply:
            var values: [BuildingID: Int] = [:]
            for building in world.buildings {
                switch building.category {
                case .housing: values[building.id] = bucket(building.residents == 0 ? 0 : building.supplyRatio)
                case .production: values[building.id] = bucket(building.isPaused ? 0 : building.efficiency)
                default: break
                }
            }
            return values
        case .coverage:
            return Dictionary(uniqueKeysWithValues: world.buildings
                .filter { $0.category == .storage || $0.category == .stop }
                .map { ($0.id, $0.cell.x &* 1000 &+ $0.cell.z) })
        }
    }

    /// Cells whose centre lies within carrier range of a building of the category.
    private func coverage(of category: BuildingCategory, in world: WorldState) -> Set<GridPoint> {
        let terrain = world.terrain
        let range = world.rules.carrierRangeMeters
        let radius = Int((range / terrain.cellSize).rounded(.up))
        var cells = Set<GridPoint>()
        for building in world.buildings where building.category == category {
            for dz in -radius...radius {
                for dx in -radius...radius {
                    let cell = building.cell.offset(dx: dx, dz: dz)
                    if terrain.contains(cell), terrain.center(of: cell).distance(to: building.center) <= range {
                        cells.insert(cell)
                    }
                }
            }
        }
        return cells
    }

    private func add(_ cells: Set<GridPoint>, color: GameColor, to root: Entity, lift: Float) {
        add(builder.fillQuads(cells: cells, material: 0), lift: lift, color: color, opacity: 0.22, to: root)
        add(builder.outlineQuads(cells: cells, material: 0, width: 0.8) { cells.contains($0) }, lift: lift + 0.02, color: color, opacity: 0.9, to: root)
    }

    private func add(_ quads: [GroundQuad], lift: Float, color: GameColor, opacity: Float, to root: Entity) {
        guard let mesh = builder.makeMesh(quads: quads, lift: lift, steps: 1, name: "overlay") else { return }
        root.addChild(ModelEntity(mesh: mesh, materials: [MaterialLibrary.shared.unlit(color, opacity: opacity)]))
    }
}
