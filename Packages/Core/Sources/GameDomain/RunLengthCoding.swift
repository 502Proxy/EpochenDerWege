/// Stores long arrays with repeating values compactly: `[a, a, a, b]` becomes
/// `[(a, 3), (b, 1)]`. Used for per-cell map data such as biomes and deposits,
/// which come in large patches.
public struct RunLengthEncoded<Value: Hashable & Codable & Sendable>: Codable, Hashable, Sendable {
    public struct Run: Codable, Hashable, Sendable {
        public var value: Value
        public var count: Int
    }

    public var runs: [Run]

    public init(_ values: [Value]) {
        var runs: [Run] = []
        for value in values {
            if let last = runs.last, last.value == value {
                runs[runs.count - 1].count += 1
            } else {
                runs.append(Run(value: value, count: 1))
            }
        }
        self.runs = runs
    }

    public var values: [Value] {
        runs.flatMap { Array(repeating: $0.value, count: $0.count) }
    }

    public var count: Int {
        runs.reduce(0) { $0 + $1.count }
    }
}
