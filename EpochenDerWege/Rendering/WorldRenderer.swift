import AppKit
import RealityKit
import Simulation
import simd

/// Baut die 3D-Szene aus dem Simulationszustand und hält sie jeden Frame aktuell.
/// Die Simulation rechnet in Metern ab (0, 0); die Szene ist um die Kartenmitte zentriert.
@MainActor
final class WorldRenderer {
    let root: AnchorEntity
    let halfExtent: Float

    private let simulation: Simulation
    private var terrain: Terrain { simulation.terrain }

    private var buildingVisuals: [Int: BuildingVisual] = [:]
    private var carrierEntities: [Int: ModelEntity] = [:]
    private var treeEntity: ModelEntity?
    private var treeSignature = -1

    private let ghost: ModelEntity
    private var ghostKey = ""
    private let selectionRing: ModelEntity

    private var buildingMaterials: [String: SimpleMaterial] = [:]
    private var roofMaterials: [String: SimpleMaterial] = [:]
    private var goodMaterials: [String: SimpleMaterial] = [:]
    private let emptyCarrierMaterial: SimpleMaterial
    private let carrierMesh: MeshResource
    private let markerMesh: MeshResource
    private let markerMaterials: [MarkerState: UnlitMaterial]

    init(simulation: Simulation) {
        self.simulation = simulation
        halfExtent = Float(simulation.terrain.extent / 2)
        root = AnchorEntity(world: SIMD3<Float>(-halfExtent, 0, -halfExtent))
        ghost = ModelEntity()
        emptyCarrierMaterial = WorldRenderer.matte(NSColor(white: 0.35, alpha: 1))
        carrierMesh = MeshResource.generateSphere(radius: 1.3)
        markerMesh = MeshResource.generateSphere(radius: 1.1)
        markerMaterials = [
            .good: UnlitMaterial(color: NSColor(srgbRed: 0.30, green: 0.85, blue: 0.35, alpha: 1)),
            .warning: UnlitMaterial(color: NSColor(srgbRed: 1.00, green: 0.80, blue: 0.20, alpha: 1)),
            .problem: UnlitMaterial(color: NSColor(srgbRed: 0.95, green: 0.25, blue: 0.20, alpha: 1)),
        ]

        var ringMaterial = UnlitMaterial(color: NSColor(white: 1, alpha: 1))
        ringMaterial.blending = .transparent(opacity: 0.55)
        selectionRing = ModelEntity(
            mesh: .generateBox(width: 11, height: 0.4, depth: 11, cornerRadius: 0.2),
            materials: [ringMaterial]
        )
        selectionRing.isEnabled = false

        for definition in simulation.data.buildings {
            let color = WorldRenderer.color(definition.color)
            buildingMaterials[definition.id] = WorldRenderer.matte(color)
            roofMaterials[definition.id] = WorldRenderer.matte(color.blended(withFraction: 0.45, of: .black) ?? color)
        }
        for good in simulation.data.goods {
            goodMaterials[good.id] = WorldRenderer.matte(WorldRenderer.color(good.color))
        }
    }

    func install(in arView: ARView) {
        arView.scene.addAnchor(root)
        root.addChild(makeTerrainEntity())
        root.addChild(makeWaterEntity())
        root.addChild(ghost)
        root.addChild(selectionRing)
        ghost.isEnabled = false

        let lights = AnchorEntity(world: .zero)
        let sun = DirectionalLight()
        sun.light.color = NSColor(srgbRed: 1.0, green: 0.96, blue: 0.88, alpha: 1)
        sun.light.intensity = 2800
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 1600, depthBias: 4)
        sun.look(at: .zero, from: SIMD3<Float>(-300, 500, 260), relativeTo: nil)
        lights.addChild(sun)

        let fill = DirectionalLight()
        fill.light.color = NSColor(srgbRed: 0.75, green: 0.82, blue: 1.0, alpha: 1)
        fill.light.intensity = 900
        fill.look(at: .zero, from: SIMD3<Float>(300, 250, -260), relativeTo: nil)
        lights.addChild(fill)
        arView.scene.addAnchor(lights)
    }

    // MARK: - Koordinaten

    func scenePosition(_ point: WorldPoint, lift: Float = 0) -> SIMD3<Float> {
        SIMD3<Float>(Float(point.x) - halfExtent, groundHeight(point) + lift, Float(point.z) - halfExtent)
    }

    func worldPoint(fromScene p: SIMD3<Float>) -> WorldPoint {
        WorldPoint(x: Double(p.x + halfExtent), z: Double(p.z + halfExtent))
    }

    /// Geländehöhe; über Wasser die Wasseroberfläche.
    func groundHeight(_ point: WorldPoint) -> Float {
        Float(max(terrain.height(at: point), terrain.seaLevel))
    }

    /// Schnittpunkt eines Sichtstrahls (Szenen-Koordinaten) mit dem Gelände.
    func groundPoint(origin: SIMD3<Float>, direction: SIMD3<Float>) -> WorldPoint? {
        let dir = simd_normalize(direction)
        let stepLength: Float = 2
        let maxDistance: Float = 8000

        func isAbove(_ t: Float) -> Bool {
            let p = origin + dir * t
            return p.y > groundHeight(worldPoint(fromScene: p))
        }

        guard isAbove(0) else { return nil }
        var low: Float = 0
        var high: Float = stepLength
        while high < maxDistance {
            if !isAbove(high) {
                for _ in 0..<12 {
                    let mid = (low + high) / 2
                    if isAbove(mid) { low = mid } else { high = mid }
                }
                return worldPoint(fromScene: origin + dir * high)
            }
            low = high
            high += stepLength
        }
        return nil
    }

    // MARK: - Gelände

    private static let biomeColors: [Biome: NSColor] = [
        .water: NSColor(srgbRed: 0.55, green: 0.50, blue: 0.36, alpha: 1),
        .sand: NSColor(srgbRed: 0.87, green: 0.80, blue: 0.56, alpha: 1),
        .grass: NSColor(srgbRed: 0.47, green: 0.66, blue: 0.30, alpha: 1),
        .forest: NSColor(srgbRed: 0.27, green: 0.47, blue: 0.20, alpha: 1),
        .rock: NSColor(srgbRed: 0.52, green: 0.50, blue: 0.47, alpha: 1),
        .snow: NSColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1),
    ]

    /// Low-Poly-Gelände: jede Kachel besteht aus zwei flach schattierten Dreiecken.
    private func makeTerrainEntity() -> Entity {
        let t = terrain
        let biomes = Biome.allCases
        var materialIndex: [Biome: UInt32] = [:]
        for (i, biome) in biomes.enumerated() {
            materialIndex[biome] = UInt32(i)
        }

        var mesh = TriangleMeshBuilder(capacity: t.size * t.size * 2)
        let cs = Float(t.cellSize)
        func vertex(_ x: Int, _ z: Int) -> SIMD3<Float> {
            SIMD3<Float>(Float(x) * cs, Float(t.vertexHeight(x, z)), Float(z) * cs)
        }
        for z in 0..<t.size {
            for x in 0..<t.size {
                let material = materialIndex[t.biome(at: GridPoint(x: x, z: z))] ?? 0
                let p00 = vertex(x, z)
                let p10 = vertex(x + 1, z)
                let p01 = vertex(x, z + 1)
                let p11 = vertex(x + 1, z + 1)
                mesh.addTriangle(p00, p01, p10, material: material, outward: SIMD3<Float>(0, 1, 0))
                mesh.addTriangle(p10, p01, p11, material: material, outward: SIMD3<Float>(0, 1, 0))
            }
        }

        let materials = biomes.map { WorldRenderer.matte(WorldRenderer.biomeColors[$0] ?? .magenta) }
        guard let resource = mesh.makeResource(name: "terrain") else { return Entity() }
        return ModelEntity(mesh: resource, materials: materials)
    }

    private func makeWaterEntity() -> Entity {
        var water = PhysicallyBasedMaterial()
        water.baseColor = .init(tint: NSColor(srgbRed: 0.20, green: 0.45, blue: 0.70, alpha: 1))
        water.roughness = 0.2
        water.metallic = 0
        water.blending = .transparent(opacity: 0.8)
        let size = Float(terrain.extent)
        let entity = ModelEntity(mesh: .generatePlane(width: size, depth: size), materials: [water])
        entity.position = SIMD3<Float>(halfExtent, Float(terrain.seaLevel) + 0.3, halfExtent)
        return entity
    }

    /// Bäume als Low-Poly-Pyramiden in einem einzigen Mesh. Wird neu gebaut, wenn sich Gebäude ändern.
    private func rebuildTrees() {
        treeEntity?.removeFromParent()
        treeEntity = nil

        let t = terrain
        var mesh = TriangleMeshBuilder(capacity: t.size * t.size)
        for z in 0..<t.size {
            for x in 0..<t.size {
                let cell = GridPoint(x: x, z: z)
                guard t.biome(at: cell) == .forest, simulation.building(at: cell) == nil else { continue }
                for k in 0..<2 {
                    let seed = hash(x, z, k)
                    let jx = Double(seed % 1000) / 1000 * 0.7 + 0.15
                    let jz = Double((seed / 1000) % 1000) / 1000 * 0.7 + 0.15
                    let point = WorldPoint(x: (Double(x) + jx) * t.cellSize, z: (Double(z) + jz) * t.cellSize)
                    let base = SIMD3<Float>(Float(point.x), Float(t.height(at: point)), Float(point.z))
                    let height: Float = 7 + Float(seed % 5)
                    addTree(to: &mesh, base: base, radius: 2.4, height: height, material: UInt32(seed % 2))
                }
            }
        }

        let materials = [
            WorldRenderer.matte(NSColor(srgbRed: 0.16, green: 0.38, blue: 0.16, alpha: 1)),
            WorldRenderer.matte(NSColor(srgbRed: 0.22, green: 0.45, blue: 0.18, alpha: 1)),
        ]
        guard let resource = mesh.makeResource(name: "trees") else { return }
        let entity = ModelEntity(mesh: resource, materials: materials)
        root.addChild(entity)
        treeEntity = entity
    }

    private func addTree(to mesh: inout TriangleMeshBuilder, base: SIMD3<Float>, radius r: Float, height: Float, material: UInt32) {
        let bottom = base + SIMD3<Float>(0, 1.2, 0)
        let apex = base + SIMD3<Float>(0, height, 0)
        let corners = [
            bottom + SIMD3<Float>(-r, 0, -r),
            bottom + SIMD3<Float>(r, 0, -r),
            bottom + SIMD3<Float>(r, 0, r),
            bottom + SIMD3<Float>(-r, 0, r),
        ]
        for i in 0..<4 {
            let a = corners[i]
            let b = corners[(i + 1) % 4]
            let outward = (a + b) / 2 - bottom
            mesh.addTriangle(a, b, apex, material: material, outward: outward)
        }
    }

    private func hash(_ x: Int, _ z: Int, _ k: Int) -> Int {
        var h = UInt64(truncatingIfNeeded: x &* 73_856_093 ^ z &* 19_349_663 ^ k &* 83_492_791)
        h = (h ^ (h >> 13)) &* 0x5bd1_e995
        h ^= h >> 15
        return Int(h % 1_000_000_007)
    }

    // MARK: - Abgleich mit der Simulation

    func sync(selectedBuildingID: Int?) {
        syncBuildings()
        syncCarriers()

        let signature = simulation.buildings.reduce(simulation.buildings.count) { $0 &* 31 &+ $1.id }
        if signature != treeSignature {
            treeSignature = signature
            rebuildTrees()
        }

        if let id = selectedBuildingID, let building = simulation.building(id: id) {
            selectionRing.isEnabled = true
            let c = building.center
            selectionRing.position = SIMD3<Float>(Float(c.x), groundHeight(c) + 0.3, Float(c.z))
        } else {
            selectionRing.isEnabled = false
        }
    }

    private func syncBuildings() {
        var alive = Set<Int>()
        for building in simulation.buildings {
            alive.insert(building.id)
            let visual: BuildingVisual
            if let existing = buildingVisuals[building.id] {
                visual = existing
            } else {
                visual = makeBuildingVisual(building)
                buildingVisuals[building.id] = visual
            }
            let state = markerState(for: building)
            if state != visual.markerState {
                visual.markerState = state
                if let material = markerMaterials[state] {
                    visual.marker.model?.materials = [material]
                    visual.marker.isEnabled = true
                } else {
                    visual.marker.isEnabled = false
                }
            }
        }
        for id in Array(buildingVisuals.keys) where !alive.contains(id) {
            buildingVisuals[id]?.body.removeFromParent()
            buildingVisuals[id] = nil
        }
    }

    private func syncCarriers() {
        var alive = Set<Int>()
        for carrier in simulation.carriers {
            alive.insert(carrier.id)
            let entity: ModelEntity
            if let existing = carrierEntities[carrier.id] {
                entity = existing
            } else {
                entity = ModelEntity(mesh: carrierMesh, materials: [goodMaterials[carrier.good] ?? emptyCarrierMaterial])
                root.addChild(entity)
                carrierEntities[carrier.id] = entity
            }
            let p = carrier.position
            entity.position = SIMD3<Float>(Float(p.x), groundHeight(p) + 1.5, Float(p.z))
            if !carrier.isLoaded && entity.scale.x > 0.75 {
                entity.model?.materials = [emptyCarrierMaterial]
                entity.scale = SIMD3<Float>(repeating: 0.7)
            }
        }
        for id in Array(carrierEntities.keys) where !alive.contains(id) {
            carrierEntities[id]?.removeFromParent()
            carrierEntities[id] = nil
        }
    }

    // MARK: - Gebäude

    private func dimensions(for category: BuildingCategory) -> SIMD3<Float> {
        switch category {
        case .housing: return SIMD3<Float>(5.5, 4.5, 5.5)
        case .production: return SIMD3<Float>(6.5, 5.5, 6.5)
        case .storage: return SIMD3<Float>(7.5, 4.5, 7.5)
        }
    }

    private func makeBuildingVisual(_ building: Building) -> BuildingVisual {
        let size = dimensions(for: building.definition.category)
        // Der Sockel reicht 3 m in den Boden, damit Gebäude am Hang nicht schweben.
        let sink: Float = 3
        let body = ModelEntity(
            mesh: .generateBox(width: size.x, height: size.y + sink, depth: size.z, cornerRadius: 0.3),
            materials: [buildingMaterials[building.definition.id] ?? WorldRenderer.matte(.magenta)]
        )
        let ground = groundHeight(building.center)
        body.position = SIMD3<Float>(Float(building.center.x), ground + (size.y - sink) / 2, Float(building.center.z))

        let roof = ModelEntity(
            mesh: .generateBox(width: size.x * 0.8, height: 1.4, depth: size.z * 0.8, cornerRadius: 0.4),
            materials: [roofMaterials[building.definition.id] ?? WorldRenderer.matte(.darkGray)]
        )
        roof.position = SIMD3<Float>(0, (size.y + sink) / 2 + 0.7, 0)
        body.addChild(roof)

        let marker = ModelEntity(mesh: markerMesh, materials: [])
        marker.position = SIMD3<Float>(0, (size.y + sink) / 2 + 4, 0)
        marker.isEnabled = false
        body.addChild(marker)

        root.addChild(body)
        return BuildingVisual(body: body, marker: marker)
    }

    private func markerState(for building: Building) -> MarkerState {
        switch building.status {
        case .working:
            return .good
        case .missingInput, .outputFull:
            return .warning
        case .noWorkers, .noResources:
            return .problem
        case .housing:
            if building.residents == 0 || building.lastSupply < 0.5 { return .problem }
            if building.lastSupply < 0.9 { return .warning }
            return .hidden
        case .idle, .storing:
            return .hidden
        }
    }

    // MARK: - Bauvorschau

    func updateGhost(definition: BuildingDefinition?, cell: GridPoint?, valid: Bool) {
        guard let definition, let cell else {
            ghost.isEnabled = false
            return
        }
        let key = "\(definition.id)-\(valid)"
        if key != ghostKey {
            ghostKey = key
            let size = dimensions(for: definition.category)
            var material = UnlitMaterial(color: valid
                ? NSColor(srgbRed: 0.35, green: 0.9, blue: 0.4, alpha: 1)
                : NSColor(srgbRed: 0.95, green: 0.3, blue: 0.25, alpha: 1))
            material.blending = .transparent(opacity: 0.45)
            ghost.model = ModelComponent(
                mesh: .generateBox(width: size.x, height: size.y, depth: size.z, cornerRadius: 0.3),
                materials: [material]
            )
        }
        let size = dimensions(for: definition.category)
        let center = terrain.cellCenter(cell)
        ghost.position = SIMD3<Float>(Float(center.x), groundHeight(center) + size.y / 2, Float(center.z))
        ghost.isEnabled = true
    }

    // MARK: - Hilfen

    static func color(_ rgb: [Double]) -> NSColor {
        guard rgb.count >= 3 else { return .magenta }
        return NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
    }

    static func matte(_ color: NSColor) -> SimpleMaterial {
        SimpleMaterial(color: color, roughness: 0.9, isMetallic: false)
    }
}

enum MarkerState {
    case hidden, good, warning, problem
}

@MainActor
final class BuildingVisual {
    let body: ModelEntity
    let marker: ModelEntity
    var markerState: MarkerState = .hidden

    init(body: ModelEntity, marker: ModelEntity) {
        self.body = body
        self.marker = marker
    }
}

/// Sammelt flach schattierte Dreiecke mit je einem Material und erzeugt daraus ein Mesh.
struct TriangleMeshBuilder {
    private var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var indices: [UInt32] = []
    private var faceMaterials: [UInt32] = []

    init(capacity triangles: Int) {
        positions.reserveCapacity(triangles * 3)
        normals.reserveCapacity(triangles * 3)
        indices.reserveCapacity(triangles * 3)
        faceMaterials.reserveCapacity(triangles)
    }

    /// Fügt ein Dreieck hinzu. Die Reihenfolge wird so gedreht, dass die Vorderseite zu `outward` zeigt.
    mutating func addTriangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, material: UInt32, outward: SIMD3<Float>) {
        var p1 = b
        var p2 = c
        var normal = simd_cross(b - a, c - a)
        let length = simd_length(normal)
        guard length > 0.000_001 else { return }
        normal /= length
        if simd_dot(normal, outward) < 0 {
            swap(&p1, &p2)
            normal = -normal
        }
        let start = UInt32(positions.count)
        positions.append(contentsOf: [a, p1, p2])
        normals.append(contentsOf: [normal, normal, normal])
        indices.append(contentsOf: [start, start + 1, start + 2])
        faceMaterials.append(material)
    }

    @MainActor
    func makeResource(name: String) -> MeshResource? {
        guard !indices.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        descriptor.materials = .perFace(faceMaterials)
        return try? MeshResource.generate(from: [descriptor])
    }
}
