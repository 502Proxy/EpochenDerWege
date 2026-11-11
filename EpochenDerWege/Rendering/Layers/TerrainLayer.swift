import AppKit
import GameDomain
import RealityKit
import simd

/// Ground, water and vegetation.
///
/// The ground is split into tiles of `chunkSize` cells. Each tile is drawn at a detail
/// level that depends on its distance to the camera, from a vertex every half cell
/// close up to one every eight cells far away; a short skirt along the tile edges
/// hides the seams between levels. Tiles change level a few at a time, nearest first,
/// so the frame rate stays smooth while the camera moves.
///
/// The ground texture is painted on a background task; until it is ready the ground
/// shows a plain colour. Vegetation is merged into one mesh per tile and exists only
/// near the camera; far away, forests are part of the texture.
final class TerrainLayer: SceneLayer {
    static let chunkSize = 32
    /// Metres between vertices per detail level, as a multiple of the cell size.
    static let levelSteps: [Double] = [0.5, 1, 2, 4, 8]
    /// Camera distance in metres up to which a level is used.
    static let levelDistances: [Float] = [700, 1500, 3000, 6000]
    /// A tile switches to a coarser level only this much beyond the threshold, so it
    /// does not flicker between two levels at the boundary.
    static let hysteresis: Float = 1.15
    /// Tiles rebuilt per frame at most.
    static let groundBudget = 6
    /// Vegetation is built within this camera distance and removed beyond `vegetationRemoval`.
    static let vegetationDistance: Float = 900
    static let vegetationRemoval: Float = 1150
    static let vegetationBudget = 2

    private let parent: Entity
    private let space: SceneSpace
    private var groundChunks: [ChunkKey: GroundChunk] = [:]
    /// Centre of each tile on the ground, for distance checks every frame.
    private var chunkCentres: [ChunkKey: SIMD3<Float>] = [:]
    private var groundMaterial: any RealityKit.Material
    private var vegetationChunks: [ChunkKey: ModelEntity] = [:]
    private var occupiedCellsByChunk: [ChunkKey: Set<GridPoint>] = [:]
    private var lastBuildingIDs: [BuildingID] = []
    private var lastRoads: Set<GridPoint> = []
    private var textureTask: Task<Void, Never>?

    private struct GroundChunk {
        let entity: ModelEntity
        let level: Int
    }

    /// Materials of the vegetation meshes, indexed by `Part`.
    private static let vegetationColors = [
        GameColor(red: 0.40, green: 0.28, blue: 0.17),
        GameColor(red: 0.15, green: 0.35, blue: 0.17),
        GameColor(red: 0.30, green: 0.52, blue: 0.20),
        GameColor(red: 0.38, green: 0.58, blue: 0.22),
        GameColor(red: 0.50, green: 0.49, blue: 0.47),
        GameColor(red: 0.33, green: 0.50, blue: 0.20),
    ]

    private enum Part: UInt32 {
        case trunk = 0, needles, leaves, lightLeaves, boulder, bush
    }

    private static let placeholderGround = GameColor(red: 0.42, green: 0.60, blue: 0.29)
    private static let waterColor = GameColor(red: 0.16, green: 0.40, blue: 0.62)

    init(parent: Entity, space: SceneSpace) {
        self.parent = parent
        self.space = space
        groundMaterial = MaterialLibrary.shared.matte(Self.placeholderGround)
        // Start with every tile at the coarsest level; detail follows the camera.
        let coarsest = Self.levelSteps.count - 1
        let tileSize = Double(Self.chunkSize) * space.terrain.cellSize
        for key in allChunks() {
            let x = (Double(key.x) + 0.5) * tileSize
            let z = (Double(key.z) + 0.5) * tileSize
            chunkCentres[key] = SIMD3<Float>(Float(x), Float(space.surface.surfaceHeight(at: WorldPoint(x: x, z: z))), Float(z))
            setGround(key, level: coarsest)
        }
        parent.addChild(makeWater())
        paintTexture()
    }

    deinit {
        textureTask?.cancel()
    }

    func update(with context: RenderContext) {
        updateOccupancy(context.world)
        updateGroundDetail(camera: context.camera)
        updateVegetation(camera: context.camera)
    }

    /// Vegetation gives way to buildings, roads and towns.
    private func updateOccupancy(_ world: WorldState) {
        let ids = world.buildings.map(\.id)
        guard ids != lastBuildingIDs || world.roads != lastRoads else { return }
        lastBuildingIDs = ids
        lastRoads = world.roads

        var occupied: [ChunkKey: Set<GridPoint>] = [:]
        for cell in world.buildings.map(\.cell) + Array(world.roads) + world.towns.flatMap(\.footprint) {
            occupied[ChunkKey(cell), default: []].insert(cell)
        }
        let changed = Set(occupied.keys).union(occupiedCellsByChunk.keys).filter {
            occupied[$0] != occupiedCellsByChunk[$0]
        }
        occupiedCellsByChunk = occupied
        // Only tiles that currently show vegetation need a rebuild; others build it when the camera comes near.
        for key in changed where vegetationChunks[key] != nil {
            rebuildVegetation(in: key)
        }
    }

    // MARK: - Detail levels

    private func distance(from camera: SIMD3<Float>, to key: ChunkKey) -> Float {
        chunkCentres[key].map { simd_distance(camera, $0) } ?? .infinity
    }

    private func level(forDistance distance: Float, current: Int?) -> Int {
        let wanted = Self.levelDistances.firstIndex { distance <= $0 } ?? Self.levelDistances.count
        // Become coarser only when clearly beyond the threshold.
        if let current, wanted > current, distance <= Self.levelDistances[min(current, Self.levelDistances.count - 1)] * Self.hysteresis {
            return current
        }
        return wanted
    }

    private func updateGroundDetail(camera: SIMD3<Float>) {
        var pending: [(key: ChunkKey, level: Int, distance: Float)] = []
        for (key, chunk) in groundChunks {
            let distance = distance(from: camera, to: key)
            let wanted = level(forDistance: distance, current: chunk.level)
            if wanted != chunk.level {
                pending.append((key, wanted, distance))
            }
        }
        // Nearest tiles first, a few per frame.
        for change in pending.sorted(by: { $0.distance < $1.distance }).prefix(Self.groundBudget) {
            setGround(change.key, level: change.level)
        }
    }

    private func updateVegetation(camera: SIMD3<Float>) {
        var missing: [(key: ChunkKey, distance: Float)] = []
        for key in groundChunks.keys {
            let distance = distance(from: camera, to: key)
            if vegetationChunks[key] == nil, distance <= Self.vegetationDistance {
                missing.append((key, distance))
            } else if let entity = vegetationChunks[key], distance > Self.vegetationRemoval {
                entity.removeFromParent()
                vegetationChunks[key] = nil
            }
        }
        for item in missing.sorted(by: { $0.distance < $1.distance }).prefix(Self.vegetationBudget) {
            rebuildVegetation(in: item.key)
        }
    }

    // MARK: - Ground and water

    /// Replaces a tile's mesh with one at the given detail level.
    private func setGround(_ key: ChunkKey, level: Int) {
        guard let mesh = makeGroundMesh(key, step: Self.levelSteps[level]) else { return }
        if let existing = groundChunks[key] {
            existing.entity.model?.mesh = mesh
            groundChunks[key] = GroundChunk(entity: existing.entity, level: level)
        } else {
            let entity = ModelEntity(mesh: mesh, materials: [groundMaterial])
            parent.addChild(entity)
            groundChunks[key] = GroundChunk(entity: entity, level: level)
        }
    }

    /// A smooth tile mesh with a vertex every `step` cells, plus a skirt along its edges.
    private func makeGroundMesh(_ key: ChunkKey, step cellsPerStep: Double) -> MeshResource? {
        let terrain = space.terrain
        let surface = space.surface
        let step = terrain.cellSize * cellsPerStep
        let originX = Double(key.x * Self.chunkSize) * terrain.cellSize
        let originZ = Double(key.z * Self.chunkSize) * terrain.cellSize
        let cellsX = min(Self.chunkSize, terrain.size - key.x * Self.chunkSize)
        let cellsZ = min(Self.chunkSize, terrain.size - key.z * Self.chunkSize)
        let columns = Int((Double(cellsX) / cellsPerStep).rounded(.up))
        let rows = Int((Double(cellsZ) / cellsPerStep).rounded(.up))
        guard columns > 0, rows > 0 else { return nil }
        let maxX = originX + Double(cellsX) * terrain.cellSize
        let maxZ = originZ + Double(cellsZ) * terrain.cellSize

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        positions.reserveCapacity((columns + 1) * (rows + 1) + 2 * (columns + rows + 2))
        func addVertex(x: Double, z: Double, drop: Float = 0) {
            positions.append(SIMD3<Float>(Float(x), Float(surface.height(x: x, z: z)) - drop, Float(z)))
            normals.append(surface.normal(x: x, z: z, step: step))
            // RealityKit samples textures with v = 0 at the bottom of the image;
            // image rows run along z from the top, hence the flip.
            uvs.append(SIMD2<Float>(Float(x / terrain.extent), Float(1 - z / terrain.extent)))
        }
        for row in 0...rows {
            for column in 0...columns {
                addVertex(x: min(maxX, originX + Double(column) * step), z: min(maxZ, originZ + Double(row) * step))
            }
        }
        var indices: [UInt32] = []
        indices.reserveCapacity(columns * rows * 6)
        let width = UInt32(columns + 1)
        for row in 0..<UInt32(rows) {
            for column in 0..<UInt32(columns) {
                let a = row * width + column
                let b = a + 1
                let c = a + width
                let d = c + 1
                // Counter-clockwise seen from above.
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        // Skirt: the outline once more, lowered, joined to the edge by faces seen from both sides.
        let drop = Float(step) * 0.6 + 2
        var outline: [UInt32] = []
        for column in 0...columns { outline.append(UInt32(column)) }
        for row in 1...rows { outline.append(UInt32(row) * width + UInt32(columns)) }
        for column in stride(from: columns - 1, through: 0, by: -1) { outline.append(UInt32(rows) * width + UInt32(column)) }
        for row in stride(from: rows - 1, through: 1, by: -1) { outline.append(UInt32(row) * width) }
        let skirtStart = UInt32(positions.count)
        for index in outline {
            let top = positions[Int(index)]
            addVertex(x: Double(top.x), z: Double(top.z), drop: drop)
        }
        for (offset, index) in outline.enumerated() {
            let next = outline[(offset + 1) % outline.count]
            let low = skirtStart + UInt32(offset)
            let lowNext = skirtStart + UInt32((offset + 1) % outline.count)
            indices.append(contentsOf: [index, low, next, next, low, lowNext])
            indices.append(contentsOf: [index, next, low, next, lowNext, low])
        }

        var descriptor = MeshDescriptor(name: "ground-\(key.x)-\(key.z)")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    /// Paints the ground texture on a background task and applies it when done.
    private func paintTexture() {
        // About two metres per pixel, between 2048 and 4096 pixels per edge.
        let size = min(4096, max(2048, space.terrain.size * 4))
        let builder = TerrainTextureBuilder(surface: space.surface, size: size)
        textureTask = Task { [weak self] in
            let pixels = await Self.paint(builder)
            guard !Task.isCancelled, let self else { return }
            self.applyTexture(pixels: pixels, size: builder.size)
        }
    }

    @concurrent
    private nonisolated static func paint(_ builder: TerrainTextureBuilder) async -> [UInt8] {
        builder.makePixels()
    }

    private func applyTexture(pixels: [UInt8], size: Int) {
        guard
            let image = TerrainTextureBuilder.makeImage(pixels: pixels, size: size),
            let texture = try? TextureResource(image: image, options: .init(semantic: .color))
        else { return }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(texture: .init(texture))
        material.roughness = 0.95
        material.metallic = 0.0
        groundMaterial = material
        for chunk in groundChunks.values {
            chunk.entity.model?.materials = [material]
        }
    }

    private func makeWater() -> Entity {
        var water = PhysicallyBasedMaterial()
        water.baseColor = .init(tint: NSColor(Self.waterColor))
        water.roughness = 0.08
        water.metallic = 0.0
        water.specular = 0.9
        water.blending = .transparent(opacity: 0.82)
        let size = Float(space.terrain.extent)
        let entity = ModelEntity(mesh: .generatePlane(width: size, depth: size), materials: [water])
        entity.position = SIMD3<Float>(size / 2, Float(space.terrain.seaLevel) + 0.3, size / 2)
        return entity
    }

    // MARK: - Vegetation

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

    /// Forests get three trees per cell; grassland has bushes and the odd tree;
    /// rocky ground has boulders. Positions are stable per cell, so nothing jumps
    /// when a chunk is rebuilt.
    private func rebuildVegetation(in key: ChunkKey) {
        vegetationChunks[key]?.removeFromParent()
        vegetationChunks[key] = nil

        let terrain = space.terrain
        let surface = space.surface
        let occupied = occupiedCellsByChunk[key] ?? []
        var mesh = TriangleMeshBuilder(estimatedTriangles: Self.chunkSize * Self.chunkSize * 60)
        let startX = key.x * Self.chunkSize
        let startZ = key.z * Self.chunkSize

        func spot(_ x: Int, _ z: Int, _ index: Int) -> (base: SIMD3<Float>, seed: Int) {
            let seed = Self.hash(x, z, index)
            let jitterX = Double(seed % 1000) / 1000 * 0.8 + 0.1
            let jitterZ = Double((seed / 1000) % 1000) / 1000 * 0.8 + 0.1
            let px = (Double(x) + jitterX) * terrain.cellSize
            let pz = (Double(z) + jitterZ) * terrain.cellSize
            return (SIMD3<Float>(Float(px), Float(surface.height(x: px, z: pz)), Float(pz)), seed)
        }

        for z in startZ..<min(startZ + Self.chunkSize, terrain.size) {
            for x in startX..<min(startX + Self.chunkSize, terrain.size) {
                let cell = GridPoint(x: x, z: z)
                guard !occupied.contains(cell) else { continue }
                switch terrain.deposit(at: cell) {
                case .stone:
                    for index in 0..<3 {
                        let (base, seed) = spot(x, z, 20 + index)
                        Self.addBoulder(to: &mesh, base: base, size: 0.9 + Float(seed % 5) * 0.25)
                    }
                    continue
                case .vines:
                    // Three rows of vines across the cell.
                    for row in 0..<3 {
                        for column in 0..<3 {
                            let px = (Double(x) + 0.2 + Double(column) * 0.3) * terrain.cellSize
                            let pz = (Double(z) + 0.2 + Double(row) * 0.3) * terrain.cellSize
                            let base = SIMD3<Float>(Float(px), Float(surface.height(x: px, z: pz)), Float(pz))
                            Self.addBush(to: &mesh, base: base, size: 0.55)
                        }
                    }
                    continue
                case nil:
                    break
                }
                switch terrain.biome(at: cell) {
                case .forest:
                    for index in 0..<3 {
                        let (base, seed) = spot(x, z, index)
                        let size = 0.75 + Float(seed % 6) * 0.08
                        if seed % 5 < 3 {
                            Self.addConifer(to: &mesh, base: base, size: size)
                        } else {
                            Self.addDeciduous(to: &mesh, base: base, size: size, light: seed % 2 == 0)
                        }
                    }
                case .grass:
                    let (base, seed) = spot(x, z, 7)
                    if seed % 100 < 6 {
                        Self.addDeciduous(to: &mesh, base: base, size: 0.9, light: true)
                    } else if seed % 100 < 22 {
                        Self.addBush(to: &mesh, base: base, size: 0.7 + Float(seed % 4) * 0.15)
                    }
                case .rock:
                    let (base, seed) = spot(x, z, 9)
                    if seed % 100 < 30 {
                        Self.addBoulder(to: &mesh, base: base, size: 0.8 + Float(seed % 5) * 0.3)
                    }
                case .sand, .water, .snow:
                    break
                }
            }
        }

        guard let resource = try? mesh.makeMesh(named: "vegetation-\(key.x)-\(key.z)") else { return }
        let entity = ModelEntity(mesh: resource, materials: Self.vegetationColors.map { MaterialLibrary.shared.matte($0) })
        parent.addChild(entity)
        vegetationChunks[key] = entity
    }

    private static func addBush(to mesh: inout TriangleMeshBuilder, base: SIMD3<Float>, size: Float) {
        addCrown(to: &mesh, center: base + SIMD3<Float>(0, 0.7 * size, 0), radius: 1.2 * size, height: 0.8 * size, sides: 5, material: Part.bush.rawValue)
    }

    private static func addBoulder(to mesh: inout TriangleMeshBuilder, base: SIMD3<Float>, size: Float) {
        addCrown(to: &mesh, center: base + SIMD3<Float>(0, 0.3 * size, 0), radius: 1.1 * size, height: 0.9 * size, sides: 5, material: Part.boulder.rawValue)
    }

    /// A conifer: short trunk and two stacked six-sided cones.
    private static func addConifer(to mesh: inout TriangleMeshBuilder, base: SIMD3<Float>, size: Float) {
        addPrism(to: &mesh, base: base, radius: 0.35 * size, height: 1.6 * size, sides: 4, material: Part.trunk.rawValue)
        addCone(to: &mesh, base: base + SIMD3<Float>(0, 1.2 * size, 0), radius: 2.4 * size, height: 4.2 * size, sides: 6, material: Part.needles.rawValue)
        addCone(to: &mesh, base: base + SIMD3<Float>(0, 3.6 * size, 0), radius: 1.7 * size, height: 3.6 * size, sides: 6, material: Part.needles.rawValue)
    }

    /// A broadleaf tree: trunk and a faceted, roughly round crown.
    private static func addDeciduous(to mesh: inout TriangleMeshBuilder, base: SIMD3<Float>, size: Float, light: Bool) {
        addPrism(to: &mesh, base: base, radius: 0.35 * size, height: 3 * size, sides: 4, material: Part.trunk.rawValue)
        let center = base + SIMD3<Float>(0, 4.6 * size, 0)
        let material = (light ? Part.lightLeaves : Part.leaves).rawValue
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
