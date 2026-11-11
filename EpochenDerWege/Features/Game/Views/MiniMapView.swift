import GameDomain
import SwiftUI

/// Overview of the whole map in the bottom right corner.
///
/// The terrain image is painted once on a background task with the same painter as
/// the 3D ground. Roads, buildings and the camera are drawn on top and follow the
/// game. Clicking or dragging moves the camera there.
struct MiniMapView: View {
    let viewModel: GameViewModel

    @State private var terrainImage: CGImage?

    static let side: CGFloat = 196
    private nonisolated static let textureSize = 256
    private static let roadColor = Color(red: 0.86, green: 0.78, blue: 0.62)

    var body: some View {
        let content = viewModel.miniMap
        let camera = viewModel.camera

        ZStack {
            if let terrainImage {
                Image(decorative: terrainImage, scale: 1)
                    .resizable()
                    .interpolation(.medium)
            } else {
                GameTheme.raised
            }
            Canvas { context, size in
                Self.draw(content, camera: camera, in: &context, size: size)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(RoundedRectangle(cornerRadius: GameTheme.smallCornerRadius))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in focus(at: value.location, mapSize: content.mapSize) }
        )
        .padding(6)
        .gamePanel()
        .help(Text("Click to move the camera"))
        .task {
            let terrain = viewModel.world.terrain
            let pixels = await Self.paint(terrain)
            terrainImage = TerrainTextureBuilder.makeImage(pixels: pixels, size: Self.textureSize)
        }
    }

    private func focus(at location: CGPoint, mapSize: Int) {
        let scale = CGFloat(mapSize) / Self.side
        let x = Int((location.x * scale).rounded(.down))
        let z = Int((location.y * scale).rounded(.down))
        guard (0..<mapSize).contains(x), (0..<mapSize).contains(z) else { return }
        viewModel.focus(on: GridPoint(x: x, z: z))
    }

    @concurrent
    private nonisolated static func paint(_ terrain: Terrain) async -> [UInt8] {
        TerrainTextureBuilder(surface: TerrainSurface(terrain: terrain), size: textureSize).makePixels()
    }

    // MARK: - Drawing

    private static func draw(_ content: MiniMapContent, camera: CameraPose?, in context: inout GraphicsContext, size: CGSize) {
        let cell = size.width / CGFloat(max(content.mapSize, 1))

        var roads = Path()
        for road in content.roads {
            roads.addRect(CGRect(x: CGFloat(road.x) * cell, y: CGFloat(road.z) * cell, width: cell, height: cell))
        }
        context.fill(roads, with: .color(roadColor))

        let marker = max(cell * 1.6, 3)
        for building in content.buildings {
            let rect = CGRect(
                x: (CGFloat(building.cell.x) + 0.5) * cell - marker / 2,
                y: (CGFloat(building.cell.z) + 0.5) * cell - marker / 2,
                width: marker,
                height: marker
            )
            context.fill(Path(rect), with: .color(Color(building.color)))
            context.stroke(Path(rect), with: .color(.black.opacity(0.5)), lineWidth: 0.5)
        }

        for town in content.towns {
            let point = CGPoint(x: (CGFloat(town.cell.x) + 0.5) * cell, y: (CGFloat(town.cell.z) + 0.5) * cell)
            let radius: CGFloat = 4
            let dot = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            context.fill(dot, with: .color(GameTheme.accent))
            context.stroke(dot, with: .color(.black.opacity(0.6)), lineWidth: 1)
            let label = Text(verbatim: town.name)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            context.draw(label, at: CGPoint(x: point.x, y: point.y - 10), anchor: .bottom)
        }

        guard let camera else { return }
        let center = CGPoint(x: CGFloat(camera.x) * cell, y: CGFloat(camera.z) * cell)
        let length: CGFloat = 26
        let spread = 0.6
        func tip(_ angle: Double) -> CGPoint {
            CGPoint(x: center.x - CGFloat(sin(angle)) * length, y: center.y - CGFloat(cos(angle)) * length)
        }
        var cone = Path()
        cone.move(to: center)
        cone.addLine(to: tip(camera.yaw - spread))
        cone.addLine(to: tip(camera.yaw + spread))
        cone.closeSubpath()
        context.fill(cone, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.55), .white.opacity(0.05)]),
            startPoint: center,
            endPoint: tip(camera.yaw)
        ))
        context.fill(Path(ellipseIn: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7)), with: .color(GameTheme.accent))
        context.stroke(Path(ellipseIn: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7)), with: .color(.black.opacity(0.6)), lineWidth: 1)
    }
}
