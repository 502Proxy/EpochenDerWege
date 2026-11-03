import GameDomain
import RealityKit
import simd

/// A horizontal rectangle on the ground, in simulation coordinates.
struct GroundQuad {
    var x0: Float
    var z0: Float
    var x1: Float
    var z1: Float
    var material: UInt32
}

/// Builds meshes that lie on the terrain: roads, zone fills and outlines, previews.
///
/// Every rectangle is subdivided and its corners are sampled from the terrain, so
/// overlays follow slopes. Different overlays use different lifts to avoid
/// z-fighting with the ground and with each other.
struct GroundOverlayBuilder {
    /// Half the road width in metres.
    static let roadHalfWidth: Float = 1.9
    static let roadLift: Float = 0.25
    static let zoneLift: Float = 0.12

    let space: SceneSpace

    /// A square on every road cell plus a strip to each neighbouring road cell, so
    /// connected cells form continuous roads.
    func makeRoadMesh(cells: Set<GridPoint>, lift: Float = roadLift, material: (GridPoint) -> UInt32 = { _ in 0 }, name: String) -> MeshResource? {
        let w = Self.roadHalfWidth
        let cellSize = Float(space.terrain.cellSize)
        var quads: [GroundQuad] = []
        quads.reserveCapacity(cells.count * 3)
        for cell in cells {
            let center = space.terrain.center(of: cell)
            let cx = Float(center.x)
            let cz = Float(center.z)
            let index = material(cell)
            quads.append(GroundQuad(x0: cx - w, z0: cz - w, x1: cx + w, z1: cz + w, material: index))
            // Strips to the east and south neighbours; west and north are added by those cells.
            if cells.contains(cell.offset(dx: 1, dz: 0)) {
                quads.append(GroundQuad(x0: cx + w, z0: cz - w, x1: cx + cellSize - w, z1: cz + w, material: index))
            }
            if cells.contains(cell.offset(dx: 0, dz: 1)) {
                quads.append(GroundQuad(x0: cx - w, z0: cz + w, x1: cx + w, z1: cz + cellSize - w, material: index))
            }
        }
        return makeMesh(quads: quads, lift: lift, name: name)
    }

    /// Any set of rectangles, each draped on the terrain.
    func makeMesh(quads: [GroundQuad], lift: Float, steps: Int = 2, name: String) -> MeshResource? {
        guard !quads.isEmpty else { return nil }
        var mesh = TriangleMeshBuilder(estimatedTriangles: quads.count * steps * steps * 2)
        let up = SIMD3<Float>(0, 1, 0)
        for quad in quads {
            func point(_ i: Int, _ j: Int) -> SIMD3<Float> {
                let x = quad.x0 + (quad.x1 - quad.x0) * Float(i) / Float(steps)
                let z = quad.z0 + (quad.z1 - quad.z0) * Float(j) / Float(steps)
                return space.local(WorldPoint(x: Double(x), z: Double(z)), lift: lift)
            }
            for i in 0..<steps {
                for j in 0..<steps {
                    mesh.addTriangle(point(i, j), point(i, j + 1), point(i + 1, j), material: quad.material, outward: up)
                    mesh.addTriangle(point(i + 1, j), point(i, j + 1), point(i + 1, j + 1), material: quad.material, outward: up)
                }
            }
        }
        return try? mesh.makeMesh(named: name)
    }

    /// One quad per cell, inset from the cell edges.
    func fillQuads(cells: Set<GridPoint>, material: UInt32, inset: Float = 0) -> [GroundQuad] {
        let size = Float(space.terrain.cellSize)
        return cells.map { cell in
            let x0 = Float(cell.x) * size
            let z0 = Float(cell.z) * size
            return GroundQuad(x0: x0 + inset, z0: z0 + inset, x1: x0 + size - inset, z1: z0 + size - inset, material: material)
        }
    }

    /// Strips along every cell edge that borders a cell outside the region.
    ///
    /// - Parameters:
    ///   - width: Width of the strips, drawn inside the cell edge.
    ///   - isInside: Whether a neighbouring cell belongs to the same region.
    func outlineQuads(cells: Set<GridPoint>, material: UInt32, width: Float = 0.7, isInside: (GridPoint) -> Bool) -> [GroundQuad] {
        let size = Float(space.terrain.cellSize)
        var quads: [GroundQuad] = []
        for cell in cells {
            let x0 = Float(cell.x) * size
            let z0 = Float(cell.z) * size
            let x1 = x0 + size
            let z1 = z0 + size
            if !isInside(cell.offset(dx: -1, dz: 0)) { quads.append(GroundQuad(x0: x0, z0: z0, x1: x0 + width, z1: z1, material: material)) }
            if !isInside(cell.offset(dx: 1, dz: 0)) { quads.append(GroundQuad(x0: x1 - width, z0: z0, x1: x1, z1: z1, material: material)) }
            if !isInside(cell.offset(dx: 0, dz: -1)) { quads.append(GroundQuad(x0: x0, z0: z0, x1: x1, z1: z0 + width, material: material)) }
            if !isInside(cell.offset(dx: 0, dz: 1)) { quads.append(GroundQuad(x0: x0, z0: z1 - width, x1: x1, z1: z1, material: material)) }
        }
        return quads
    }
}
