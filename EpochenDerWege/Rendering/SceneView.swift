import AppKit
import Combine
import GameDomain
import GameSimulation
import RealityKit
import SwiftUI

/// Hosts the RealityKit scene inside SwiftUI.
///
/// `ARView` is used instead of `RealityView` because the game needs low-level mouse
/// input (right-drag, scroll wheel, hover) and screen-to-world ray casts. See
/// `docs/Architecture.md` for the reasoning.
struct SceneView: NSViewRepresentable {
    let viewModel: GameViewModel
    let engine: SimulationEngine

    func makeCoordinator() -> SceneCoordinator {
        SceneCoordinator(viewModel: viewModel, engine: engine)
    }

    func makeNSView(context: Context) -> ARView {
        context.coordinator.makeView()
    }

    func updateNSView(_ nsView: ARView, context: Context) {}

    static func dismantleNSView(_ nsView: ARView, coordinator: SceneCoordinator) {
        coordinator.tearDown()
    }
}

/// Drives the scene every frame and translates mouse and keyboard input.
///
/// Controls:
/// - Click: build or select · Drag: move the map · Right-drag: rotate and tilt
/// - Scroll or pinch: zoom · WASD or arrows: move · Q/E: rotate
/// - Right-click or Esc: cancel · Space: pause
final class SceneCoordinator: NSObject {
    private let viewModel: GameViewModel
    private let engine: SimulationEngine
    private let camera = PerspectiveCamera()
    private var rig = CameraRig()
    private weak var view: ARView?
    private var renderer: SceneRenderer?
    private var frameSubscription: (any Cancellable)?
    private var eventMonitors: [Any] = []

    private var hoverPoint: CGPoint?
    private var animationTime: TimeInterval = 0
    private var handledFocus = 0
    private var cachedPreview: (point: CGPoint, tick: Int, tool: BuildingTypeID, preview: PlacementPreview?)?
    /// Start and current end of a drag with an area tool (road, zone).
    private var areaDrag: (start: GridPoint, end: GridPoint)?
    private var cachedRoadPreview: (start: GridPoint, end: GridPoint, tick: Int, preview: RoadPreview)?

    init(viewModel: GameViewModel, engine: SimulationEngine) {
        self.viewModel = viewModel
        self.engine = engine
        super.init()
    }

    func makeView() -> ARView {
        let view = ARView(frame: .zero)
        view.environment.background = .color(NSColor(srgbRed: 0.63, green: 0.78, blue: 0.92, alpha: 1))

        let world = engine.snapshots.value.world
        let renderer = SceneRenderer(world: world)
        renderer.install(in: view)
        self.renderer = renderer

        camera.camera.fieldOfViewInDegrees = 45
        camera.camera.near = 1
        // Far enough to see across an 8 km map from the highest zoom.
        camera.camera.far = 30000
        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(camera)
        view.scene.addAnchor(cameraAnchor)

        rig.bounds = renderer.space.halfExtent
        if let start = world.startCell {
            rig.target = renderer.space.scene(world.terrain.center(of: start))
        }
        applyCamera()

        installGestures(on: view)
        installEventMonitors()
        frameSubscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            let deltaTime = event.deltaTime
            MainActor.assumeIsolated {
                self?.renderFrame(deltaTime: deltaTime)
            }
        }

        self.view = view
        return view
    }

    func tearDown() {
        frameSubscription?.cancel()
        frameSubscription = nil
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
    }

    // MARK: - Frame

    private func renderFrame(deltaTime: TimeInterval) {
        guard let renderer else { return }
        if let window = view?.window, !window.acceptsMouseMovedEvents {
            window.acceptsMouseMovedEvents = true
        }

        let frame = engine.snapshots.value
        animationTime += deltaTime * Double(engine.speed)
        let context = RenderContext(
            frame: frame,
            fraction: frame.interpolationFraction(at: .now),
            selectedBuildingID: viewModel.selectedBuildingID,
            preview: placementPreview(in: frame.world),
            roadPreview: roadPreview(in: frame.world),
            zonePreview: zonePreview(),
            animationTime: animationTime,
            overlay: viewModel.overlay,
            camera: rig.position + SIMD3<Float>(renderer.space.halfExtent, 0, renderer.space.halfExtent)
        )
        renderer.update(with: context)

        if let focus = viewModel.cameraFocus, focus.id != handledFocus {
            handledFocus = focus.id
            rig.target = renderer.space.scene(frame.world.terrain.center(of: focus.cell))
            rig.distance = min(rig.distance, 160)
        }

        // The camera follows the terrain height below its target, smoothed.
        let ground = Float(renderer.space.surface.surfaceHeight(at: renderer.space.worldPoint(fromScene: rig.target)))
        rig.target.y += (ground - rig.target.y) * min(1, Float(deltaTime) * 8)
        applyCamera()

        let look = renderer.space.worldPoint(fromScene: rig.target)
        let cellSize = renderer.space.terrain.cellSize
        viewModel.reportCamera(CameraPose(x: look.x / cellSize, z: look.z / cellSize, yaw: Double(rig.yaw)))
    }

    private func applyCamera() {
        camera.look(at: rig.target, from: rig.position, relativeTo: nil)
    }

    // MARK: - Picking

    private func cell(at point: CGPoint) -> GridPoint? {
        guard let view, let renderer, let ray = view.ray(through: point) else { return nil }
        guard let hit = renderer.space.groundPoint(origin: ray.origin, direction: ray.direction) else { return nil }
        return renderer.space.terrain.cell(containing: hit)
    }

    /// The ghost building under the mouse. Ray casts only when the mouse, the tool
    /// or the world changed, not on every frame.
    private func placementPreview(in world: WorldState) -> PlacementPreview? {
        guard
            let tool = viewModel.selectedBuildingType,
            let definition = world.catalog.building(tool),
            let point = hoverPoint
        else {
            cachedPreview = nil
            return nil
        }
        if let cached = cachedPreview, cached.point == point, cached.tick == world.clock.tick, cached.tool == tool {
            return cached.preview
        }
        let preview = cell(at: point).map { cell in
            PlacementPreview(definition: definition, cell: cell, isValid: viewModel.previewValidity(at: cell, in: world) ?? false)
        }
        cachedPreview = (point, world.clock.tick, tool, preview)
        return preview
    }

    /// Road under construction: the dragged path, or the hovered cell before dragging.
    private func roadPreview(in world: WorldState) -> RoadPreview? {
        guard viewModel.selectedTool == .road else {
            cachedRoadPreview = nil
            return nil
        }
        let ends: (start: GridPoint, end: GridPoint)
        if let areaDrag {
            ends = areaDrag
        } else if let point = hoverPoint, let cell = cell(at: point) {
            ends = (cell, cell)
        } else {
            return nil
        }
        if let cached = cachedRoadPreview, cached.start == ends.start, cached.end == ends.end, cached.tick == world.clock.tick {
            return cached.preview
        }
        let path = RoadPlanner.path(from: ends.start, to: ends.end)
        let plan = RoadPlanner.plan(path, in: world)
        let buildable = Set(plan.map(\.cell))
        let tunnels = Set(plan.filter { $0.kind == .tunnel }.map(\.cell))
        let preview = RoadPreview(cells: path, valid: buildable.union(path.filter(world.hasRoad(at:))), tunnels: tunnels)
        cachedRoadPreview = (ends.start, ends.end, world.clock.tick, preview)
        return preview
    }

    /// Rectangle being zoned while a zone tool is dragged.
    private func zonePreview() -> ZonePreview? {
        guard let areaDrag else { return nil }
        switch viewModel.selectedTool {
        case .zone(let kind):
            return ZonePreview(cells: Set(ZonePlanner.rectangle(from: areaDrag.start, to: areaDrag.end)), kind: kind)
        case .unzone:
            return ZonePreview(cells: Set(ZonePlanner.rectangle(from: areaDrag.start, to: areaDrag.end)), kind: nil)
        default:
            return nil
        }
    }

    // MARK: - Gestures

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

        view.addGestureRecognizer(NSMagnificationGestureRecognizer(target: self, action: #selector(handlePinch(_:))))
    }

    /// Vertical movement, positive upwards regardless of the view's coordinate system.
    private func upwardDelta(_ translation: CGPoint, in view: NSView) -> Float {
        Float(view.isFlipped ? -translation.y : translation.y)
    }

    @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
        guard let view else { return }
        viewModel.click(on: cell(at: gesture.location(in: view)))
    }

    @objc private func handleRightClick(_ gesture: NSClickGestureRecognizer) {
        viewModel.cancel()
    }

    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
        guard let view else { return }
        if viewModel.selectedTool?.drawsArea == true {
            handleAreaDrag(gesture, in: view)
            return
        }
        let translation = gesture.translation(in: view)
        rig.drag(dx: Float(translation.x), dy: upwardDelta(translation, in: view))
        gesture.setTranslation(.zero, in: view)
        applyCamera()
    }

    /// With an area tool, dragging marks cells from the start cell to the cell under the mouse.
    private func handleAreaDrag(_ gesture: NSPanGestureRecognizer, in view: NSView) {
        let location = gesture.location(in: view)
        switch gesture.state {
        case .began:
            let translation = gesture.translation(in: view)
            let origin = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
            if let start = cell(at: origin) ?? cell(at: location) {
                areaDrag = (start, start)
            }
        case .changed:
            if let drag = areaDrag, let end = cell(at: location) {
                areaDrag = (drag.start, end)
            }
        case .ended:
            if let drag = areaDrag {
                viewModel.applyDrag(from: drag.start, to: drag.end)
            }
            areaDrag = nil
        default:
            areaDrag = nil
        }
    }

    @objc private func handleOrbit(_ gesture: NSPanGestureRecognizer) {
        guard let view else { return }
        let translation = gesture.translation(in: view)
        rig.rotate(dx: Float(translation.x), dy: upwardDelta(translation, in: view))
        gesture.setTranslation(.zero, in: view)
        applyCamera()
    }

    @objc private func handlePinch(_ gesture: NSMagnificationGestureRecognizer) {
        rig.zoom(by: Float(1 - gesture.magnification))
        gesture.magnification = 0
        applyCamera()
    }

    // MARK: - Scroll wheel, mouse movement, keyboard

    private func locationInView(_ event: NSEvent) -> CGPoint? {
        guard let view, event.window === view.window else { return nil }
        let point = view.convert(event.locationInWindow, from: nil)
        return view.bounds.contains(point) ? point : nil
    }

    private func installEventMonitors() {
        // Local monitors are always called on the main thread.
        let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.locationInView(event) != nil else { return false }
                let sensitivity: Float = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
                self.rig.zoom(by: exp(-Float(event.scrollingDeltaY) * sensitivity))
                self.applyCamera()
                return true
            }
            return handled ? nil : event
        }

        let movement = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hoverPoint = self.locationInView(event)
            }
            return event
        }

        let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, let view = self.view, event.window === view.window else { return false }
                return self.handleKey(code: event.keyCode)
            }
            return handled ? nil : event
        }

        eventMonitors = [scroll, movement, keys].compactMap { $0 }
    }

    private enum KeyCode {
        static let a: UInt16 = 0, s: UInt16 = 1, d: UInt16 = 2, q: UInt16 = 12, w: UInt16 = 13, e: UInt16 = 14
        static let space: UInt16 = 49, escape: UInt16 = 53, o: UInt16 = 31
        static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
    }

    private func handleKey(code: UInt16) -> Bool {
        switch code {
        case KeyCode.w, KeyCode.up: rig.move(forward: 1, right: 0)
        case KeyCode.s, KeyCode.down: rig.move(forward: -1, right: 0)
        case KeyCode.a, KeyCode.left: rig.move(forward: 0, right: -1)
        case KeyCode.d, KeyCode.right: rig.move(forward: 0, right: 1)
        case KeyCode.q: rig.rotate(dx: -40, dy: 0)
        case KeyCode.e: rig.rotate(dx: 40, dy: 0)
        case KeyCode.space: viewModel.togglePause()
        case KeyCode.o: viewModel.cycleOverlay()
        case KeyCode.escape: viewModel.cancel()
        default: return false
        }
        applyCamera()
        return true
    }
}
