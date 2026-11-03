import Foundation
import simd

/// Orbit-Kamera wie in Aufbauspielen: schaut auf einen Punkt am Boden,
/// lässt sich drehen, neigen, zoomen und über die Karte schieben.
struct CameraRig {
    /// Punkt, auf den die Kamera schaut (Szenen-Koordinaten).
    var target = SIMD3<Float>(0, 0, 0)
    /// Drehung um die Hochachse (Bogenmaß).
    var yaw: Float = .pi * 0.25
    /// Neigung über dem Horizont (Bogenmaß).
    var pitch: Float = 0.75
    var distance: Float = 220

    /// Halbe Kartenbreite – so weit darf das Ziel vom Mittelpunkt weg.
    var bounds: Float = 512

    static let minDistance: Float = 25
    static let maxDistance: Float = 1400
    static let minPitch: Float = 0.2
    static let maxPitch: Float = 1.45

    var position: SIMD3<Float> {
        let horizontal = cos(pitch) * distance
        return target + SIMD3<Float>(sin(yaw) * horizontal, sin(pitch) * distance, cos(yaw) * horizontal)
    }

    /// Blickrichtung am Boden (ohne Höhe).
    var forward: SIMD3<Float> {
        SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
    }

    var right: SIMD3<Float> {
        SIMD3<Float>(cos(yaw), 0, -sin(yaw))
    }

    /// Verschiebt die Karte wie beim Ziehen mit der Maus. `dy` ist positiv, wenn nach oben gezogen wird.
    mutating func drag(dx: Float, dy: Float) {
        let scale = distance * 0.0018
        target += (-right * dx - forward * dy) * scale
        clamp()
    }

    /// Bewegt die Kamera in Blickrichtung (Tastatur).
    mutating func move(forwardAmount: Float, rightAmount: Float) {
        let scale = distance * 0.06
        target += (forward * forwardAmount + right * rightAmount) * scale
        clamp()
    }

    mutating func rotate(dx: Float, dy: Float) {
        yaw -= dx * 0.006
        pitch = min(max(pitch + dy * 0.004, CameraRig.minPitch), CameraRig.maxPitch)
    }

    mutating func zoom(factor: Float) {
        distance = min(max(distance * factor, CameraRig.minDistance), CameraRig.maxDistance)
    }

    private mutating func clamp() {
        target.x = min(max(target.x, -bounds), bounds)
        target.z = min(max(target.z, -bounds), bounds)
    }
}
