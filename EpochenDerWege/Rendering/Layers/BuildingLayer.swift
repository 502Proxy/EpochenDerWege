import GameDomain
import RealityKit
import simd

/// Buildings with a coloured status marker above them.
///
/// Models come from `BuildingModelFactory`. Entities are created when a building
/// appears in a snapshot and removed when it disappears. Markers only change their
/// material when the status changes; rotors (mill sails) turn while the building works.
final class BuildingLayer: SceneLayer {
    /// Rotor speed in radians per second of game time at 1×.
    private static let rotorSpeed: Float = 1.2

    private let parent: Entity
    private let space: SceneSpace
    private let factory = BuildingModelFactory()
    private var visuals: [BuildingID: Visual] = [:]

    init(parent: Entity, space: SceneSpace) {
        self.parent = parent
        self.space = space
    }

    func update(with context: RenderContext) {
        var alive = Set<BuildingID>()
        for building in context.world.buildings {
            alive.insert(building.id)
            let visual = visuals[building.id] ?? makeVisual(for: building)
            visuals[building.id] = visual
            visual.show(MarkerState(building))
            if let rotor = visual.rotor, building.status == .working {
                rotor.orientation = simd_quatf(angle: Float(context.animationTime) * Self.rotorSpeed, axis: SIMD3<Float>(0, 0, 1))
            }
        }
        for (id, visual) in visuals where !alive.contains(id) {
            visual.root.removeFromParent()
            visuals[id] = nil
        }
    }

    /// Footprint and height of the placement preview per category (width, height, depth).
    static func previewSize(of category: BuildingCategory) -> SIMD3<Float> {
        switch category {
        case .housing: SIMD3<Float>(5.5, 5, 5.5)
        case .production: SIMD3<Float>(7, 5.5, 7)
        case .storage: SIMD3<Float>(7.5, 5, 7.5)
        case .commerce: SIMD3<Float>(6.5, 5, 6.5)
        case .stop: SIMD3<Float>(5, 3.5, 5)
        }
    }

    private func makeVisual(for building: Building) -> Visual {
        let model = factory.makeModel(for: building.definition)
        model.root.position = space.local(building.center)
        // Quarter-turn variety, stable per cell, keeps buildings aligned to the grid.
        let turns = (building.cell.x &* 31 &+ building.cell.z &* 17) & 3
        model.root.orientation = simd_quatf(angle: Float(turns) * .pi / 2, axis: SIMD3<Float>(0, 1, 0))

        let marker = ModelEntity(mesh: MaterialLibrary.shared.sphere(radius: 1.1), materials: [])
        marker.position = SIMD3<Float>(0, model.markerHeight, 0)
        marker.isEnabled = false
        model.root.addChild(marker)

        parent.addChild(model.root)
        return Visual(root: model.root, marker: marker, rotor: model.rotor)
    }

    /// What the marker above a building shows.
    enum MarkerState: Equatable {
        case hidden, good, warning, problem

        init(_ building: Building) {
            switch building.status {
            case .working:
                self = .good
            case .missingInput, .outputFull:
                self = .warning
            case .noWorkers, .noResources:
                self = .problem
            case .housing:
                if building.residents == 0 || building.supplyRatio < 0.5 {
                    self = .problem
                } else if building.supplyRatio < 0.9 {
                    self = .warning
                } else {
                    self = .hidden
                }
            case .awaitingGoods, .paused:
                self = .warning
            case .idle, .storing, .trading:
                self = .hidden
            }
        }

        var color: GameColor? {
            switch self {
            case .hidden: nil
            case .good: .markerGood
            case .warning: .markerWarning
            case .problem: .markerProblem
            }
        }
    }

    private final class Visual {
        let root: Entity
        let marker: ModelEntity
        let rotor: Entity?
        private var state: MarkerState = .hidden

        init(root: Entity, marker: ModelEntity, rotor: Entity?) {
            self.root = root
            self.marker = marker
            self.rotor = rotor
        }

        func show(_ newState: MarkerState) {
            guard newState != state else { return }
            state = newState
            if let color = newState.color {
                marker.model?.materials = [MaterialLibrary.shared.unlit(color)]
                marker.isEnabled = true
            } else {
                marker.isEnabled = false
            }
        }
    }
}
