/// A stock of goods with a fixed capacity per good.
public struct Inventory: Hashable, Sendable, Codable {
    public private(set) var items: [GoodID: Int] = [:]
    public let capacityPerGood: Int

    public init(capacityPerGood: Int) {
        self.capacityPerGood = capacityPerGood
    }

    public func count(of good: GoodID) -> Int {
        items[good, default: 0]
    }

    /// Free space for a good.
    public func space(for good: GoodID) -> Int {
        max(0, capacityPerGood - count(of: good))
    }

    public var total: Int {
        items.values.reduce(0, +)
    }

    public var isEmpty: Bool {
        items.isEmpty
    }

    /// Non-empty stock sorted by good, so iteration order is deterministic.
    public var sortedItems: [GoodAmount] {
        items.keys.sorted().map { GoodAmount(good: $0, amount: items[$0, default: 0]) }
    }

    public func contains(_ amount: GoodAmount) -> Bool {
        count(of: amount.good) >= amount.amount
    }

    /// Adds up to `amount` units and returns how many fitted.
    @discardableResult
    public mutating func add(_ good: GoodID, amount: Int) -> Int {
        let added = min(amount, space(for: good))
        if added > 0 {
            items[good, default: 0] += added
        }
        return added
    }

    /// Removes up to `amount` units and returns how many were removed.
    @discardableResult
    public mutating func remove(_ good: GoodID, amount: Int) -> Int {
        let removed = min(amount, count(of: good))
        if removed > 0 {
            let rest = count(of: good) - removed
            items[good] = rest > 0 ? rest : nil
        }
        return removed
    }
}
