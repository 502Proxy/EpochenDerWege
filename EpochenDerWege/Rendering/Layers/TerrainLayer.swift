import AppKit
import GameDomain
import RealityKit

/// Ground, water and forest.
///
/// The ground mesh is built once. Trees are split into chunks so that placing a
/// building only rebuilds the trees of one chunk instead of the whole forest.
final class TerrainLayer: SceneLayer {
    static let chunkSize = 16

    private let parent: Entity
    private let space: SceneSpace
    private var treeChunks: [ChunkKey: ModelEntity] = [:]
    private var occupiedCellsByChunk: [ChunkKey: Set<GridPoint>] = [:]
    private var lastBuildingIDs: [BuildingID] = []
    private var lastRoads: Set<GridPoint> = []

    private static let biomeColors: [Biome: GameColor] = [
        .water: GameColor(red: 0.55, green: 0.50, blue: 0.36),
        .sand: GameColor(red: 0.87, green: 0.80, blue: 0.56),
        .grass: GameColor(red: 0.47, green: 0.66, blue: 0.30),
        .forest: GameColor(red: 0.27, green: 0.47, blue: 0.20),
        .rock: GameColor(red: 0.52, green: 0.50, blue: 0.47),
        .snow: GameColor(red: 0.95, green: 0.95, blue: 0.97),
    ]
    /// Materials of the tree meshes, indexed by `TreePart`.
    private static let treeColors = [
        GameColor(red: 0.40, green: 0.28, blue: 0.17),
        GameColor(red: 0.15, green: 0.35, blue: 0.17),
        GameColor(red: 0.30, green: 0.52, blue: 0.20),
        GameColor(red: 0.38, green: 0.58, blue: 0.22),
    ]

    private enum TreePart: UInt32 {
        case trunk = 0, needles, leaves, lightLeaves
    }

    /// Shades per biome; neighbouring cells pick different shades so the ground looks less uniform.
    private static let shadeSteps: [Double] = [0, 0.05, 0.10]
    private static let waterColor = GameColor(red: 0.20, green: 0.45, blue: 0.70)

    init(parent: Entity, space: SceneSpace) {
        self.parent = parent
        self.space = space
        if let ground = makeGround() {
            parent.addChild(ground)
        }
        parent.addChild(makeWater())
        for key in allChunks() {
            rebuildTrees(in: key)
        }
    }

    func update(with context: RenderContext) {
        let world = context.world
        let ids = world.buildings.map(\.id)
        guard ids != lastBuildingIDs || world.roads != lastRoads else { return }
        lastBuildingIDs = ids
        lastRoads = world.roads

        // Trees give way to buildings and roads.
        var occupied: [ChunkKey: Set<GridPoint>] = [:]
        for cell in world.buildings.map(\.cell) + Array(world.roads) {
            occupied[ChunkKey(cell), default: []].insert(cell)
        }
        let changed = Set(occupied.keys).union(occupiedCellsByChunk.keys).filter {
            occupied[$0] != occupiedCellsByChunk[$0]
        }
        occupiedCellsByChunk = occupied
        for key in changed {
            rebuildTrees(in: key)
        }
    }

    // MARK: - Ground and water

    private func makeGround() -> Entity? {
        let terrain = space.terrain
        let biomes = Biome.allCases
        let biomeIndex = Dictionary(uniqueKeysWithValues: biomes.enumerated().map { ($1, $0) })
        let shades = Self.shadeSteps.count
        let cellSize = Float(terrain.cellSize)

        func corner(_ x: Int, _ z: Int) -> SIMD3<Float> {
            SIMD3<Float>(Float(x) * cellSize, Float(terrain.cornerHeight(x: x, z: z)), Float(z) * cellSize)
        }

        var mesh = TriangleMeshBuilder(estimatedTriangles: terrain.size * terrain.size * 2)
        let up = SIMD3<Float>(0, 1, 0)
        for z in 0..<terrain.size {
            for x in 0..<terrain.size {
                let biome = biomeIndex[terrain.biome(at: GridPoint(x: x, z: z))] ?? 0
                let material = UInt32(biome * shades + Self.hash(x, z, 7) % shades)
                mesh.addTriangle(corner(x, z), corner(x, z + 1), corner(x + 1, z), material: material, outward: up)
                mesh.addTriangle(corner(x + 1, z), corner(x, z + 1), corner(x + 1, z + 1), material: material, outward: up)
            }
        }

        guard let resource = try? mesh.makeMesh(named: "terrain") else { return nil }
        let materials = biomes.flatMap { biome in
            Self.shadeSteps.map { MaterialLibrary.shared.matte((Self.biomeColors[biome] ?? .selection).darkened(by: $0)) }
        }
        return ModelEntity(mesh: resource, materials: materials)
    }

    private func makeWater() -> Entity {
        var water = PhysicallyBasedMaterial()
        water.baseColor = .init(tint: NSColor(Self.waterColor))
        water.roughness = 0.2
        water.metallic = 0.0
        water.blending = .transparent(opacity: 0.8)
        let size = Float(space.terrain.extent)
        let entity = ModelEntity(mesh: .generatePlane(width: size, depth: size), materials: [water])
        entity.position = SIMD3<Float>(size / 2, Float(space.terrain.seaLevel) + 0.3, size / 2)
        return entity
    }

    // MARK: - Trees

    private struct ChunkKey: Hashable {
        let x: Int
        let z: Int

        init(x: Int, z: Int) {
            self.x = x
            self.z = z
        }

        init(_ cell: GridPoint) {
            x = cell.x / TerrainLayer.chunkSize
            z = cell.z / TerrainLayer.chunkSize
        }
    }

    private func allChunks() -> [ChunkKey] {
        let count = (space.terrain.size + Self.chunkSize - 1) / Self.chunkSize
        return (0..<count).flatMap { z in (0..<count).map { x in ChunkKey(x: x, z: z) } }
    }

    private func rebuildTrees(in key: ChunkKey) {
        treeChunks[key]?.removeFromParent()
        treeChunks[key] = nil

        let terrain = space.terrain
        let occupied = occupiedCellsByChunk[key] ?? []
        var mesh = TriangleMeshBuilder(estimatedTriangles: Self.chunkSize * Self.chunkSize * 40)
        let startX = key.x * Self.chunkSize
        let startZ = key.z * Self.chunkSize

        for z in startZ..<min(startZ + Self.chunkSize, terrain.size) {
            for x in startX..<min(startX + Self.chunkSize, terrain.size) {
                let cell = GridPoint(x: x, z: z)
                guard terrain.biome(at: cell) == .forest, !occupied.contains(cell) else { continue }
                for index in 0..<2 {
                    let seed = Self.hash(x, z, index)
                    let jitterX = Double(seed % 1000) / 1000 * 0.7 + 0.15
                    let jitterZ = Double((seed / 1000) % 1000) / 1000 * 0.7 + 0.15
                    let point = WorldPoint(x: (Double(x) + jitterX) * terrain.cellSize, z: (Double(z) + jitterZ) * terrain.cellSize)
                    let base = SIMD3<Float>(Float(point.x), Float(terrain.height(at: point)), Float(point.z))
                    let size = 0.8 + Float(seed % 5) * 0.1
                    if seed % 5 < 3 {
                        Self.addConifer(to: &mesh, base: base, size: size)
                    } else {
                        Self.addDeciduous(to: &mesh, base: base, size: size, light: seed % 2 == 0)
                    }
                }
            }
        }

        guard let resource = try? mesh.makeMesh(named: "trees-\(key.x)-\(key.z)") else { return }
        let entity = ModelEntity(mesh: resource, materials: Self.treeColors.map { MaterialLibrary.shared.matte($0) })
        parent.addChild(entity)
        treeChunks[key] = entity
    }

    /// A conifer: short trunk and two stacked six-sided cones.
    private static func addConifer(to mesh: inout TriangleMeshBuilder, base: SIMD3<Float>, size: Float) {
        addPrism(to: &mesh, base: base, radius: 0.35 * size, height: 1.6 * size, sides: 4, material: TreePart.trunk.rawValue)
        addCone(to: &mesh, base: base + SIMD3<Float>(0, 1.2 * size, 0), radius: 2.4 * size, height: 4.2 * size, sides: 6, material: TreePart.needles.rawValue)
        addCone(to: &mesh, base: base + SIMD3<Float>(0, 3.6 * size, 0), radius: 1.7 * size, height: 3.6 * size, sides: 6, material: TreePart.needles.rawValue)
    }

    /// A broadleaf tree: trunk and a faceted, roughly round crown.
    private static func addDeciduous(to mesh: inout TriangleMeshBuilder, base: SIMD3<Float>, size: Float, light: Bool) {
        addPrism(to: &mesh, base: base, radius: 0.35 * size, height: 3 * size, sides: 4, material: TreePart.trunk.rawValue)
        let center = base + SIMD3<Float>(0, 4.6 * size, 0)
        let material = (light ? TreePart.lightLeaves : TreePart.leaves).rawValue
        addCrown(to: &mesh, center: center, radius: 2.4 * size, height: 2.2 * size, sides: 6, material: material)
    }

    private static func ring(center: SIMD3<Float>, radius: Float, sides: Int, rotation: Float = 0) -> [SIMD3<Float>] {
        (0..<sides).map { index in
            let angle = rotation + Float(index) / Float(sides) * 2 * .pi
            return center + SIMD3<Float>(cos(angle) * radius, 0, sin(angle) * radius)
        }
    }

    private static func addCone(to mesh: inout TriangleMeshBuilder, base: SIMD3<Float>, radius: Float, height: Float, sides: Int, material: UInt32) {
        let apex = base + SIMD3<Float>(0, height, 0)
        let corners = ring(center: base, radius: radius, sides: sides)
        for index in 0..<sides {
            let a = corners[index]
            let b = corners[(index + 1) % sides]
            mesh.addTriangle(a, b, apex, material: material, outward: (a + b) / 2 - base)
            mesh.addTriangle(a, b, base, material: material, outward: SIMD3<Float>(0, -1, 0))
        }
    }

    private static func addPrism(to mesh: inout TriangleMeshBuilder, base: SIMD3<Float>, radius: Float, height: Float, sides: Int, material: UInt32) {
        let bottom = ring(center: base, radius: radius, sides: sides, rotation: .pi / 4)
        let top = bottom.map { $0 + SIMD3<Float>(0, height, 0) }
        for index in 0..<sides {
            let next = (index + 1) % sides
            let outward = (bottom[index] + bottom[next]) / 2 - base
            mesh.addTriangle(bottom[index], bottom[next], top[next], material: material, outward: outward)
            mesh.addTriangle(bottom[index], top[next], top[index], material: material, outward: outward)
        }
    }

    /// Two cones joined at their bases: a cheap low-poly sphere.
    private static func addCrown(to mesh: inout TriangleMeshBuilder, center: SIMD3<Float>, radius: Float, height: Float, sides: Int, material: UInt32) {
        let top = center + SIMD3<Float>(0, height, 0)
        let bottom = center - SIMD3<Float>(0, height * 0.8, 0)
        let corners = ring(center: center, radius: radius, sides: sides)
        for index in 0..<sides {
            let a = corners[index]
            let b = corners[(index + 1) % sides]
            let side = (a + b) / 2 - center
            mesh.addTriangle(a, b, top, material: material, outward: side + SIMD3<Float>(0, 1, 0))
            mesh.addTriangle(a, b, bottom, material: material, outward: side - SIMD3<Float>(0, 1, 0))
        }
    }

    /// Stable pseudo-random number per tree, so trees do not jump when a chunk is rebuilt.
    private static func hash(_ x: Int, _ z: Int, _ index: Int) -> Int {
        var h = UInt64(truncatingIfNeeded: (x &* 73_856_093) ^ (z &* 19_349_663) ^ (index &* 83_492_791))
        h = (h ^ (h >> 13)) &* 0x5BD1_E995
        h ^= h >> 15
        return Int(h % 1_000_000_007)
    }
}
