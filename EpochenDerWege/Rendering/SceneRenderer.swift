import AppKit
import GameDomain
import GameSimulation
import RealityKit
import simd

/// Everything a layer needs to draw one frame.
struct RenderContext {
    let frame: SimulationFrame
    /// Interpolation factor between `frame.previous` and `frame.world`.
    let fraction: Double
    let selectedBuildingID: BuildingID?
    let preview: PlacementPreview?
    let roadPreview: RoadPreview?
    let zonePreview: ZonePreview?
    /// Seconds of animation time; advances with the game speed and stops while paused.
    let animationTime: TimeInterval
    let overlay: MapOverlay
    /// Camera position in simulation coordinates (below the root anchor), for detail levels.
    let camera: SIMD3<Float>

    var world: WorldState { frame.world }
}

/// Ghost building shown under the mouse while a build tool is active.
struct PlacementPreview: Equatable {
    let definition: BuildingDefinition
    let cell: GridPoint
    let isValid: Bool
}

/// Road cells shown while the road tool is active.
struct RoadPreview: Equatable {
    /// Cells of the planned path, in order.
    let cells: [GridPoint]
    /// Cells that will be (or already are) road; the others are shown as blocked.
    let valid: Set<GridPoint>
    /// New cells that will be built as tunnels.
    let tunnels: Set<GridPoint>
}

/// Area being zoned (or unzoned) while dragging a zone tool.
struct ZonePreview: Equatable {
    let cells: Set<GridPoint>
    /// `nil` when zoning is being removed.
    let kind: ZoneKind?
}

/// One part of the scene (composite pattern). Layers own their entities and update
/// them from snapshots; they never talk to the simulation directly.
protocol SceneLayer: AnyObject {
    func update(with context: RenderContext)
}

/// Builds the 3D scene from simulation snapshots and keeps it in sync every frame.
///
/// The simulation works in metres with the map origin at a corner. The scene is
/// centred on the map: the `root` anchor is shifted by half the map size, so layers
/// can place their entities directly in simulation coordinates.
final class SceneRenderer {
    let root: AnchorEntity
    let space: SceneSpace

    private let layers: [any SceneLayer]

    init(world: WorldState) {
        space = SceneSpace(terrain: world.terrain)
        root = AnchorEntity(world: SIMD3<Float>(-space.halfExtent, 0, -space.halfExtent))
        layers = [
            TerrainLayer(parent: root, space: space),
            ZoneLayer(parent: root, space: space),
            MapOverlayLayer(parent: root, space: space),
            RoadLayer(parent: root, space: space),
            BuildingLayer(parent: root, space: space),
            TownLayer(parent: root, space: space),
            CarrierLayer(parent: root, space: space),
            VehicleLayer(parent: root, space: space),
            SelectionLayer(parent: root, space: space),
            PlacementPreviewLayer(parent: root, space: space),
            RoadPreviewLayer(parent: root, space: space),
        ]
    }

    func install(in view: ARView) {
        view.scene.addAnchor(root)
        view.scene.addAnchor(Self.makeLights())
    }

    func update(with context: RenderContext) {
        for layer in layers {
            layer.update(with: context)
        }
    }

    private static func makeLights() -> AnchorEntity {
        let anchor = AnchorEntity(world: .zero)

        let sun = DirectionalLight()
        sun.light.color = NSColor(srgbRed: 1.0, green: 0.96, blue: 0.88, alpha: 1)
        sun.light.intensity = 2800
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 1600, depthBias: 4)
        sun.look(at: .zero, from: SIMD3<Float>(-300, 500, 260), relativeTo: nil)
        anchor.addChild(sun)

        let fill = DirectionalLight()
        fill.light.color = NSColor(srgbRed: 0.75, green: 0.82, blue: 1.0, alpha: 1)
        fill.light.intensity = 900
        fill.look(at: .zero, from: SIMD3<Float>(300, 250, -260), relativeTo: nil)
        anchor.addChild(fill)

        return anchor
    }
}

/// Conversions between simulation coordinates and the scene.
struct SceneSpace {
    let terrain: Terrain
    /// The smooth visible ground; see `TerrainSurface`.
    let surface: TerrainSurface

    init(terrain: Terrain) {
        self.terrain = terrain
        surface = TerrainSurface(terrain: terrain)
    }

    var halfExtent: Float { Float(terrain.extent / 2) }

    /// Position below the root anchor (simulation coordinates) on the ground surface.
    func local(_ point: WorldPoint, lift: Float = 0) -> SIMD3<Float> {
        SIMD3<Float>(Float(point.x), Float(surface.surfaceHeight(at: point)) + lift, Float(point.z))
    }

    /// Absolute scene position (for the camera) of a ground point.
    func scene(_ point: WorldPoint, lift: Float = 0) -> SIMD3<Float> {
        local(point, lift: lift) - SIMD3<Float>(halfExtent, 0, halfExtent)
    }

    func worldPoint(fromScene position: SIMD3<Float>) -> WorldPoint {
        WorldPoint(x: Double(position.x + halfExtent), z: Double(position.z + halfExtent))
    }

    /// Intersection of a view ray (scene coordinates) with the ground, found by ray marching.
    func groundPoint(origin: SIMD3<Float>, direction: SIMD3<Float>) -> WorldPoint? {
        let direction = simd_normalize(direction)
        let stepLength: Float = 2
        let maximumDistance: Float = 8000

        func isAboveGround(_ t: Float) -> Bool {
            let p = origin + direction * t
            return p.y > Float(surface.surfaceHeight(at: worldPoint(fromScene: p)))
        }

        guard isAboveGround(0) else { return nil }
        var low: Float = 0
        var high = stepLength
        while high < maximumDistance {
            if !isAboveGround(high) {
                for _ in 0..<12 {
                    let middle = (low + high) / 2
                    if isAboveGround(middle) { low = middle } else { high = middle }
                }
                return worldPoint(fromScene: origin + direction * high)
            }
            low = high
            high += stepLength
        }
        return nil
    }
}
