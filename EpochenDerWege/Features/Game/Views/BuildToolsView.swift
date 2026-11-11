import GameDomain
import SwiftUI

/// Build categories in the bottom bar. The open category's tools appear in a
/// `ToolPaletteView` above the bar.
struct BuildCategoryBar: View {
    @Binding var openCategory: ToolCategory?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ToolCategory.allCases) { category in
                let isOpen = openCategory == category
                Button {
                    openCategory = isOpen ? nil : category
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: category.symbol)
                            .font(.system(size: 17, weight: .medium))
                        Text(category.title)
                            .font(GameTheme.caption)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                }
                .buttonStyle(HUDButtonStyle(isActive: isOpen, size: CGSize(width: 74, height: 48)))
                .keyboardShortcut(KeyEquivalent(category.shortcut), modifiers: [])
                .help(Text(verbatim: "\(category.title) (\(category.shortcut))"))
                .accessibilityAddTraits(isOpen ? .isSelected : [])
            }
        }
    }
}

/// The tools of one category as cards with colour, name and price.
struct ToolPaletteView: View {
    let viewModel: GameViewModel
    let category: ToolCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category.title)
                .font(GameTheme.title)
                .padding(.horizontal, 4)
            HStack(spacing: 6) {
                ForEach(category.tools(in: viewModel.catalog), id: \.self) { tool in
                    ToolCard(
                        presentation: ToolPresentation(tool, catalog: viewModel.catalog),
                        isSelected: viewModel.selectedTool == tool,
                        action: { viewModel.toggleTool(tool) }
                    )
                }
            }
        }
        .padding(10)
        .gamePanel()
    }
}

/// Display data of a tool.
private struct ToolPresentation {
    let name: String
    let detail: String
    let costLabel: String?
    let symbol: String?
    let color: Color

    init(_ tool: BuildTool, catalog: GameCatalog) {
        switch tool {
        case .building(let type):
            let definition = catalog.building(type)
            name = GameText.buildingName(type, in: catalog)
            detail = definition.map { GameText.summary(of: $0, catalog: catalog) } ?? ""
            costLabel = definition.map { "\($0.cost)" }
            symbol = nil
            color = definition.map { Color($0.color) } ?? .gray
        case .road:
            name = String(localized: "Gravel road")
            detail = String(localized: "Drag to build. \(catalog.rules.roadCostPerCell) thalers per cell; steep cells become tunnels for \(catalog.rules.tunnelCostPerCell) thalers.")
            costLabel = "\(catalog.rules.roadCostPerCell)"
            symbol = "road.lanes"
            color = Color(red: 0.66, green: 0.60, blue: 0.50)
        case .zone(let kind):
            name = GameText.name(of: kind)
            detail = GameText.zoneDescription(kind)
            costLabel = nil
            symbol = "square.dashed.inset.filled"
            color = Color(ZoneLayer.color(of: kind))
        case .unzone:
            name = String(localized: "Remove zone")
            detail = String(localized: "Drag to remove zoning. Existing houses stay.")
            costLabel = nil
            symbol = "square.dashed"
            color = .orange
        case .line:
            name = String(localized: "New line")
            detail = String(localized: "Click stops one after another, then press Return or Create line. Buy ox carts for the line in the lines window.")
            costLabel = nil
            symbol = "point.topleft.down.to.point.bottomright.curvepath"
            color = .blue
        case .bulldoze:
            name = String(localized: "Demolish")
            detail = String(localized: "Click a building or road to remove it. Half of the cost is refunded.")
            costLabel = nil
            symbol = "trash"
            color = .red
        }
    }
}

private struct ToolCard: View {
    let presentation: ToolPresentation
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(presentation.color.gradient.opacity(presentation.symbol == nil ? 1 : 0.25))
                    if let symbol = presentation.symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(presentation.color)
                    }
                }
                .frame(width: 44, height: 30)

                Text(presentation.name)
                    .font(GameTheme.caption)
                    .lineLimit(1)
                    .foregroundStyle(GameTheme.primaryText)
                if let costLabel = presentation.costLabel {
                    Label {
                        Text(verbatim: costLabel)
                    } icon: {
                        Image(systemName: "circle.circle.fill")
                    }
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 10, design: .rounded).monospacedDigit())
                    .foregroundStyle(GameTheme.accent)
                }
            }
            .frame(width: 96, height: 84)
            .background(isSelected ? GameTheme.accent.opacity(0.22) : GameTheme.raised.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? GameTheme.accent : GameTheme.stroke, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(presentation.detail)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Small popover with the mouse and keyboard controls.
struct ControlsHelpButton: View {
    @State private var isShown = false

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Image(systemName: "questionmark")
                .font(.system(size: 15, weight: .semibold))
        }
        .buttonStyle(HUDButtonStyle(size: CGSize(width: 36, height: 36)))
        .help(Text("Controls"))
        .popover(isPresented: $isShown, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Controls").font(.headline)
                Text("Click: build or select")
                Text("Drag: move the map")
                Text("Road and zone tools: drag to draw")
                Text("Right-drag: rotate")
                Text("Scroll: zoom")
                Text("Right-click or Esc: cancel")
                Text("WASD, Q/E, Space")
                Text("1–4: open a build category")
                Text("F, G, B, L: finances, goods, buildings, lines")
            }
            .font(.callout)
            .padding(12)
        }
    }
}

extension Color {
    init(_ color: GameColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue)
    }
}
