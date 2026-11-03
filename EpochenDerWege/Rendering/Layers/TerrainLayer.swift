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

    private static let biomeColors: [Biome: GameColor] = [
        .water: GameColor(red: 0.55, green: 0.50, blue: 0.36),
        .sand: GameColor(red: 0.87, green: 0.80, blue: 0.56),
        .grass: GameColor(red: 0.47, green: 0.66, blue: 0.30),
        .forest: GameColor(red: 0.27, green: 0.47, blue: 0.20),
        .rock: GameColor(red: 0.52, green: 0.50, blue: 0.47),
        .snow: GameColor(red: 0.95, green: 0.95, blue: 0.97),
    ]
    private static let treeColors = [
        GameColor(red: 0.16, green: 0.38, blue: 0.16),
        GameColor(red: 0.22, green: 0.45, blue: 0.18),
    ]
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
        let buildings = context.world.buildings
        let ids = buildings.map(\.id)
        guard ids != lastBuildingIDs else { return }
        lastBuildingIDs = ids

        var occupied: [ChunkKey: Set<GridPoint>] = [:]
        for building in buildings {
            occupied[ChunkKey(building.cell), default: []].insert(building.cell)
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
        let materialIndex = Dictionary(uniqueKeysWithValues: biomes.enumerated().map { ($1, UInt32($0)) })
        let cellSize = Float(terrain.cellSize)

        func corner(_ x: Int, _ z: Int) -> SIMD3<Float> {
            SIMD3<Float>(Float(x) * cellSize, Float(terrain.cornerHeight(x: x, z: z)), Float(z) * cellSize)
        }

        var mesh = TriangleMeshBuilder(estimatedTriangles: terrain.size * terrain.size * 2)
        let up = SIMD3<Float>(0, 1, 0)
        for z in 0..<terrain.size {
            for x in 0..<terrain.size {
                let material = materialIndex[terrain.biome(at: GridPoint(x: x, z: z))] ?? 0
                mesh.addTriangle(corner(x, z), corner(x, z + 1), corner(x + 1, z), material: material, outward: up)
                mesh.addTriangle(corner(x + 1, z), corner(x, z + 1), corner(x + 1, z + 1), material: material, outward: up)
            }
        }

        guard let resource = try? mesh.makeMesh(named: "terrain") else { return nil }
        let materials = biomes.map { MaterialLibrary.shared.matte(Self.biomeColors[$0] ?? .selection) }
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
        var mesh = TriangleMeshBuilder(estimatedTriangles: Self.chunkSize * Self.chunkSize * 8)
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
                    Self.addTree(to: &mesh, base: base, radius: 2.4, height: 7 + Float(seed % 5), material: UInt32(seed % 2))
                }
            }
        }

        guard let resource = try? mesh.makeMesh(named: "trees-\(key.x)-\(key.z)") else { return }
        let entity = ModelEntity(mesh: resource, materials: Self.treeColors.map { MaterialLibrary.shared.matte($0) })
        parent.addChild(entity)
        treeChunks[key] = entity
    }

    /// A tree is a four-sided pyramid.
    private static func addTree(to mesh: inout TriangleMeshBuilder, base: SIMD3<Float>, radius: Float, height: Float, material: UInt32) {
        let bottom = base + SIMD3<Float>(0, 1.2, 0)
        let apex = base + SIMD3<Float>(0, height, 0)
        let corners = [
            bottom + SIMD3<Float>(-radius, 0, -radius),
            bottom + SIMD3<Float>(radius, 0, -radius),
            bottom + SIMD3<Float>(radius, 0, radius),
            bottom + SIMD3<Float>(-radius, 0, radius),
        ]
        for i in 0..<4 {
            let a = corners[i]
            let b = corners[(i + 1) % 4]
            mesh.addTriangle(a, b, apex, material: material, outward: (a + b) / 2 - bottom)
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
