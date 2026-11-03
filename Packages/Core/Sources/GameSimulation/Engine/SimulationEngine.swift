import GameDomain

/// The latest published state plus the information a renderer needs to interpolate.
public struct SimulationFrame: Sendable {
    /// State after the most recent tick.
    public let world: WorldState
    /// State before the most recent tick. Renderers interpolate from here to `world`.
    public let previous: WorldState
    /// When `world` was published.
    public let publishedAt: ContinuousClock.Instant
    /// Time until the next tick at the current speed.
    public let tickInterval: Duration

    /// Interpolation factor in `0...1` for the given moment.
    public func interpolationFraction(at now: ContinuousClock.Instant) -> Double {
        let elapsed = now - publishedAt
        guard tickInterval > .zero else { return 1 }
        return min(1, max(0, elapsed / tickInterval))
    }
}

/// Runs a ``Simulation`` on a background task at a fixed tick rate.
///
/// - Player actions are submitted as ``GameCommand``s and applied between ticks.
/// - After every tick an immutable ``SimulationFrame`` is published to ``snapshots``.
/// - The main thread only ever reads snapshots, so a slow tick can never drop a frame.
///
/// At speed 1 the engine runs ``baseTicksPerSecond`` ticks per second; at speed 4,
/// four times as many. Speed 0 pauses time but still applies commands.
public final class SimulationEngine: Sendable {
    public static let baseTicksPerSecond = 10

    /// Latest published frame. Read it from any thread.
    public let snapshots: LockedValue<SimulationFrame>

    private let commands = LockedValue<[any GameCommand]>([])
    private let speedMultiplier = LockedValue(1)
    private let pendingSimulation: LockedValue<Simulation?>
    private let loopTask = LockedValue<Task<Void, Never>?>(nil)

    public init(simulation: Simulation) {
        snapshots = LockedValue(SimulationFrame(
            world: simulation.world,
            previous: simulation.world,
            publishedAt: .now,
            tickInterval: Self.tickInterval(forSpeed: 1)
        ))
        pendingSimulation = LockedValue(simulation)
    }

    deinit {
        loopTask.value?.cancel()
    }

    /// Current speed multiplier; 0 means paused.
    public var speed: Int {
        speedMultiplier.value
    }

    public func setSpeed(_ multiplier: Int) {
        speedMultiplier.set(max(0, multiplier))
    }

    /// Queues a command. It is applied before the next tick.
    public func submit(_ command: any GameCommand) {
        commands.update { $0.append(command) }
    }

    /// Starts the background loop. Calling it again has no effect.
    public func start() {
        let simulation = pendingSimulation.update { pending -> Simulation? in
            defer { pending = nil }
            return pending
        }
        guard let simulation else { return }

        let snapshots = snapshots
        let commands = commands
        let speedMultiplier = speedMultiplier
        let task = Task.detached(priority: .userInitiated) {
            await Self.run(simulation, snapshots: snapshots, commands: commands, speed: speedMultiplier)
        }
        loopTask.set(task)
    }

    /// Stops the background loop. The last published frame stays available.
    public func stop() {
        loopTask.value?.cancel()
    }

    static func tickInterval(forSpeed multiplier: Int) -> Duration {
        .seconds(1) / (baseTicksPerSecond * max(1, multiplier))
    }

    private static func run(
        _ initial: Simulation,
        snapshots: LockedValue<SimulationFrame>,
        commands: LockedValue<[any GameCommand]>,
        speed: LockedValue<Int>
    ) async {
        var simulation = initial
        let clock = ContinuousClock()
        var deadline = clock.now

        while !Task.isCancelled {
            let multiplier = speed.value
            let previous = simulation.world

            let queued = commands.update { pending -> [any GameCommand] in
                defer { pending.removeAll() }
                return pending
            }
            for command in queued {
                simulation.execute(command)
            }
            if multiplier > 0 {
                simulation.step()
            }

            let interval = tickInterval(forSpeed: multiplier)
            snapshots.set(SimulationFrame(
                world: simulation.world,
                previous: previous,
                publishedAt: clock.now,
                tickInterval: interval
            ))

            // Fixed time step. If a tick ran late, continue from now instead of
            // trying to catch up, which would only make things worse.
            deadline = max(deadline.advanced(by: interval), clock.now)
            try? await clock.sleep(until: deadline, tolerance: .milliseconds(1))
        }
    }
}
