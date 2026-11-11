import GameDomain

/// Finds buildings near a point without looking at every building on the map.
///
/// Buildings are kept in square buckets of ``bucketSize`` metres. A range query only
/// visits the buckets the search circle touches. Results are returned in placement
/// order (ascending ``BuildingID``), the same order as `WorldState.buildings`, so
/// systems that switch to the index make exactly the same decisions as before.
struct SpatialIndex: Sendable {
    /// Edge length of a bucket in metres.
    static let bucketSize = 64.0

    private struct Bucket: Hashable, Sendable {
        let x: Int
        let z: Int

        init(_ point: WorldPoint) {
            x = Int((point.x / SpatialIndex.bucketSize).rounded(.down))
            z = Int((point.z / SpatialIndex.bucketSize).rounded(.down))
        }

        init(x: Int, z: Int) {
            self.x = x
            self.z = z
        }
    }

    private var buckets: [Bucket: [BuildingID]] = [:]

    mutating func insert(_ id: BuildingID, at point: WorldPoint) {
        buckets[Bucket(point), default: []].append(id)
    }

    mutating func remove(_ id: BuildingID, at point: WorldPoint) {
        let bucket = Bucket(point)
        buckets[bucket]?.removeAll { $0 == id }
        if buckets[bucket]?.isEmpty == true {
            buckets[bucket] = nil
        }
    }

    /// IDs in all buckets touched by the circle, ascending. Callers filter by exact distance.
    func candidates(near point: WorldPoint, radius: Double) -> [BuildingID] {
        let low = Bucket(WorldPoint(x: point.x - radius, z: point.z - radius))
        let high = Bucket(WorldPoint(x: point.x + radius, z: point.z + radius))
        var ids: [BuildingID] = []
        for z in low.z...high.z {
            for x in low.x...high.x {
                if let found = buckets[Bucket(x: x, z: z)] {
                    ids.append(contentsOf: found)
                }
            }
        }
        return ids.sorted()
    }
}
