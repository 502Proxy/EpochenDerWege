import Synchronization

/// A value shared between threads, protected by a mutex.
///
/// Reads and writes are short critical sections, so the main thread never waits
/// noticeably for the simulation thread and vice versa.
public final class LockedValue<Value: Sendable>: Sendable {
    private let storage: Mutex<Value>

    public init(_ value: Value) {
        storage = Mutex(value)
    }

    public var value: Value {
        storage.withLock { $0 }
    }

    public func set(_ newValue: Value) {
        storage.withLock { $0 = newValue }
    }

    /// Mutates the value in place and returns a result, atomically.
    @discardableResult
    public func update<Result: Sendable>(_ body: (inout Value) -> Result) -> Result {
        storage.withLock { body(&$0) }
    }
}
