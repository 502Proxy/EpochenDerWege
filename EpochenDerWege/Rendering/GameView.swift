import AppKit
import Combine
import RealityKit
import Simulation
import SwiftUI

/// Bettet die RealityKit-Ansicht in SwiftUI ein.
struct GameView: NSViewRepresentable {
    let controller: GameController

    func makeCoordinator() -> GameCoordinator {
        GameCoordinator(controller: controller)
    }

    func makeNSView(context: Context) -> ARView {
        context.coordinator.makeView()
    }

    func updateNSView(_ nsView: ARView, context: Context) {}

    static func dismantleNSView(_ nsView: ARView, coordinator: GameCoordinator) {
        coordinator.teardown()
    }
}

/// Steuert Kamera, Maus und Tastatur und treibt jeden Frame Simulation und Darstellung an.
///
/// Bedienung:
/// - Linksklick: bauen bzw. Gebäude auswählen
/// - Linke Maustaste ziehen: Karte verschieben
/// - Rechte Maustaste ziehen: drehen und neigen
/// - Rechtsklick oder Esc: Bauwerkzeug ablegen
/// - Scrollen oder Pinch: zoomen
/// - WASD / Pfeiltasten: bewegen, Q/E: drehen, Leertaste: Pause
@MainActor
final class GameCoordinator: NSObject {
    private let controller: GameController
    private weak var arView: ARView?
    private var renderer: WorldRenderer?
    private var rig = CameraRig()
    private let camera: PerspectiveCamera
    private var updateSubscription: Cancellable?
    private var eventMonitors: [Any] = []
    private var hoverPoint: CGPoint?

    init(controller: GameController) {
        self.controller = controller
        camera = PerspectiveCamera()
        super.init()
    }

    func makeView() -> ARView {
        let view = ARView(frame: .zero)
        view.environment.background = .color(NSColor(srgbRed: 0.63, green: 0.78, blue: 0.92, alpha: 1))

        let renderer = WorldRenderer(simulation: controller.simulation)
        renderer.install(in: view)
        self.renderer = renderer

        camera.camera.fieldOfViewInDegrees = 45
        camera.camera.near = 1
        camera.camera.far = 8000
        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(camera)
        view.scene.addAnchor(cameraAnchor)

        rig.bounds = renderer.halfExtent
        if let start = controller.simulation.startCell {
            rig.target = renderer.scenePosition(controller.simulation.terrain.cellCenter(start))
        }
        applyCamera()

        installGestures(on: view)
        installEventMonitors()

        updateSubscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            let dt = event.deltaTime
            MainActor.assumeIsolated {
                self?.frame(deltaTime: dt)
            }
        }

        arView = view
        return view
    }

    func teardown() {
        updateSubscription?.cancel()
        updateSubscription = nil
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
    }

    // MARK: - Frame

    private func frame(deltaTime: TimeInterval) {
        guard let renderer else { return }
        if let window = arView?.window, !window.acceptsMouseMovedEvents {
            window.acceptsMouseMovedEvents = true
        }

        controller.advance(deltaTime: deltaTime)
        renderer.sync(selectedBuildingID: controller.selectedBuildingID)
        updateGhost()

        // Die Kamera folgt der Geländehöhe unter dem Zielpunkt.
        let ground = renderer.groundHeight(renderer.worldPoint(fromScene: rig.target))
        rig.target.y += (ground - rig.target.y) * min(1, Float(deltaTime) * 8)
        applyCamera()
    }

    private func applyCamera() {
        camera.look(at: rig.target, from: rig.position, relativeTo: nil)
    }

    // MARK: - Auswahl unter dem Mauszeiger

    private func cell(at point: CGPoint) -> GridPoint? {
        guard let view = arView, let renderer, let ray = view.ray(through: point) else { return nil }
        guard let hit = renderer.groundPoint(origin: ray.origin, direction: ray.direction) else { return nil }
        return controller.simulation.terrain.cell(at: hit)
    }

    private func updateGhost() {
        guard let renderer else { return }
        guard
            let tool = controller.selectedTool,
            let definition = controller.simulation.data.building(tool),
            let point = hoverPoint,
            let cell = cell(at: point)
        else {
            renderer.updateGhost(definition: nil, cell: nil, valid: false)
            return
        }
        renderer.updateGhost(definition: definition, cell: cell, valid: controller.placementCheck(for: cell) ?? false)
    }

    // MARK: - Gesten

    private func installGestures(on view: ARView) {
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        click.buttonMask = 0x1
        view.addGestureRecognizer(click)

        let rightClick = NSClickGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
        rightClick.buttonMask = 0x2
        view.addGestureRecognizer(rightClick)

        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.buttonMask = 0x1
        view.addGestureRecognizer(pan)

        let orbit = NSPanGestureRecognizer(target: self, action: #selector(handleOrbit(_:)))
        orbit.buttonMask = 0x2
        view.addGestureRecognizer(orbit)

        let pinch = NSMagnificationGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)
    }

    /// Bewegung nach oben ist positiv, egal ob die Ansicht gespiegelt ist.
    private func upwardDelta(_ translation: CGPoint, in view: NSView) -> Float {
        Float(view.isFlipped ? -translation.y : translation.y)
    }

    @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
        guard let view = arView else { return }
        controller.handleClick(on: cell(at: gesture.location(in: view)))
    }

    @objc private func handleRightClick(_ gesture: NSClickGestureRecognizer) {
        controller.cancelTool()
    }

    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
        guard let view = arView else { return }
        let t = gesture.translation(in: view)
        rig.drag(dx: Float(t.x), dy: upwardDelta(t, in: view))
        gesture.setTranslation(.zero, in: view)
        applyCamera()
    }

    @objc private func handleOrbit(_ gesture: NSPanGestureRecognizer) {
        guard let view = arView else { return }
        let t = gesture.translation(in: view)
        rig.rotate(dx: Float(t.x), dy: upwardDelta(t, in: view))
        gesture.setTranslation(.zero, in: view)
        applyCamera()
    }

    @objc private func handlePinch(_ gesture: NSMagnificationGestureRecognizer) {
        rig.zoom(factor: Float(1 - gesture.magnification))
        gesture.magnification = 0
        applyCamera()
    }

    // MARK: - Scrollen, Mausbewegung, Tastatur

    private func isInsideView(_ event: NSEvent) -> CGPoint? {
        guard let view = arView, event.window === view.window else { return nil }
        let point = view.convert(event.locationInWindow, from: nil)
        return view.bounds.contains(point) ? point : nil
    }

    private func installEventMonitors() {
        // Die Monitore laufen immer auf dem Main Thread.
        let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.isInsideView(event) != nil else { return false }
                let sensitivity: Float = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
                self.rig.zoom(factor: exp(-Float(event.scrollingDeltaY) * sensitivity))
                self.applyCamera()
                return true
            }
            return handled ? nil : event
        }

        let move = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated {
                if let self {
                    self.hoverPoint = self.isInsideView(event)
                }
            }
            return event
        }

        let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, let view = self.arView, event.window === view.window else { return false }
                return self.handleKey(event)
            }
            return handled ? nil : event
        }

        eventMonitors = [scroll, move, keys].compactMap { $0 }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 13, 126: rig.move(forwardAmount: 1, rightAmount: 0)   // W, ↑
        case 1, 125: rig.move(forwardAmount: -1, rightAmount: 0)   // S, ↓
        case 0, 123: rig.move(forwardAmount: 0, rightAmount: -1)   // A, ←
        case 2, 124: rig.move(forwardAmount: 0, rightAmount: 1)    // D, →
        case 12: rig.rotate(dx: -40, dy: 0)                         // Q
        case 14: rig.rotate(dx: 40, dy: 0)                          // E
        case 49: controller.togglePause()                           // Leertaste
        case 53: controller.cancelTool()                            // Esc
        default: return false
        }
        applyCamera()
        return true
    }
}
