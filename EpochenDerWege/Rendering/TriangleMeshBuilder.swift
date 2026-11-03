import RealityKit
import simd

/// Collects flat-shaded triangles, each with a material index, and builds a mesh.
///
/// Flat shading (one normal per triangle) gives the low-poly look. Every triangle
/// gets its own three vertices for that reason.
struct TriangleMeshBuilder {
    private var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var indices: [UInt32] = []
    private var faceMaterials: [UInt32] = []

    init(estimatedTriangles: Int) {
        positions.reserveCapacity(estimatedTriangles * 3)
        normals.reserveCapacity(estimatedTriangles * 3)
        indices.reserveCapacity(estimatedTriangles * 3)
        faceMaterials.reserveCapacity(estimatedTriangles)
    }

    var isEmpty: Bool { indices.isEmpty }

    /// Adds a triangle. The winding is flipped if needed so the front face points towards `outward`.
    mutating func addTriangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, material: UInt32, outward: SIMD3<Float>) {
        var second = b
        var third = c
        var normal = simd_cross(b - a, c - a)
        let length = simd_length(normal)
        guard length > 1e-6 else { return }
        normal /= length
        if simd_dot(normal, outward) < 0 {
            swap(&second, &third)
            normal = -normal
        }
        let start = UInt32(positions.count)
        positions.append(contentsOf: [a, second, third])
        normals.append(contentsOf: [normal, normal, normal])
        indices.append(contentsOf: [start, start + 1, start + 2])
        faceMaterials.append(material)
    }

    func makeMesh(named name: String) throws -> MeshResource? {
        guard !isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        descriptor.materials = .perFace(faceMaterials)
        return try MeshResource.generate(from: [descriptor])
    }
}
