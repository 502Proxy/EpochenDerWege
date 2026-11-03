import GameDomain
import RealityKit

/// Buildings with a coloured status marker above them.
///
/// Entities are created when a building appears in a snapshot and removed when it
/// disappears. Markers only change their material when the status changes.
final class BuildingLayer: SceneLayer {
    private let parent: Entity
    private let space: SceneSpace
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
        }
        for (id, visual) in visuals where !alive.contains(id) {
            visual.body.removeFromParent()
            visuals[id] = nil
        }
    }

    /// Body size per category in metres (width, height, depth).
    static func size(of category: BuildingCategory) -> SIMD3<Float> {
        switch category {
        case .housing: SIMD3<Float>(5.5, 4.5, 5.5)
        case .production: SIMD3<Float>(6.5, 5.5, 6.5)
        case .storage: SIMD3<Float>(7.5, 4.5, 7.5)
        }
    }

    private func makeVisual(for building: Building) -> Visual {
        let library = MaterialLibrary.shared
        let size = Self.size(of: building.category)
        // The base reaches 3 m into the ground so buildings on slopes do not float.
        let sink: Float = 3
        let body = ModelEntity(
            mesh: library.box(SIMD3<Float>(size.x, size.y + sink, size.z)),
            materials: [library.matte(building.definition.color)]
        )
        body.position = space.local(building.center, lift: (size.y - sink) / 2)

        let roof = ModelEntity(
            mesh: library.box(SIMD3<Float>(size.x * 0.8, 1.4, size.z * 0.8), cornerRadius: 0.4),
            materials: [library.matte(building.definition.color.darkened(by: 0.45))]
        )
        roof.position = SIMD3<Float>(0, (size.y + sink) / 2 + 0.7, 0)
        body.addChild(roof)

        let marker = ModelEntity(mesh: library.sphere(radius: 1.1), materials: [])
        marker.position = SIMD3<Float>(0, (size.y + sink) / 2 + 4, 0)
        marker.isEnabled = false
        body.addChild(marker)

        parent.addChild(body)
        return Visual(body: body, marker: marker)
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
            case .idle, .storing:
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
        let body: ModelEntity
        let marker: ModelEntity
        private var state: MarkerState = .hidden

        init(body: ModelEntity, marker: ModelEntity) {
            self.body = body
            self.marker = marker
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
