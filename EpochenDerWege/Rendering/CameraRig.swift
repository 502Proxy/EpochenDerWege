import simd

/// Orbit camera as known from city builders: looks at a point on the ground and can be
/// rotated, tilted, zoomed and moved across the map. Pure math, no RealityKit.
struct CameraRig {
    /// Point the camera looks at, in scene coordinates.
    var target = SIMD3<Float>(0, 0, 0)
    /// Rotation around the vertical axis, in radians.
    var yaw: Float = .pi * 0.25
    /// Elevation above the horizon, in radians.
    var pitch: Float = 0.75
    var distance: Float = 220
    /// The target stays within ±bounds on x and z.
    var bounds: Float = 512

    static let distanceRange: ClosedRange<Float> = 25...1400
    static let pitchRange: ClosedRange<Float> = 0.2...1.45

    var position: SIMD3<Float> {
        let horizontal = cos(pitch) * distance
        return target + SIMD3<Float>(sin(yaw) * horizontal, sin(pitch) * distance, cos(yaw) * horizontal)
    }

    /// Viewing direction projected onto the ground.
    var forward: SIMD3<Float> {
        SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
    }

    var right: SIMD3<Float> {
        SIMD3<Float>(cos(yaw), 0, -sin(yaw))
    }

    /// Moves the map like dragging it with the mouse. `dy` is positive for upward drags.
    mutating func drag(dx: Float, dy: Float) {
        target += (-right * dx - forward * dy) * (distance * 0.0018)
        clampTarget()
    }

    /// Moves the camera relative to the viewing direction (keyboard).
    mutating func move(forward forwardAmount: Float, right rightAmount: Float) {
        target += (forward * forwardAmount + right * rightAmount) * (distance * 0.06)
        clampTarget()
    }

    mutating func rotate(dx: Float, dy: Float) {
        yaw -= dx * 0.006
        pitch = (pitch + dy * 0.004).clamped(to: Self.pitchRange)
    }

    mutating func zoom(by factor: Float) {
        distance = (distance * factor).clamped(to: Self.distanceRange)
    }

    private mutating func clampTarget() {
        target.x = target.x.clamped(to: -bounds...bounds)
        target.z = target.z.clamped(to: -bounds...bounds)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
