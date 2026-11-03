import GameDomain
import SwiftUI

/// Build toolbar at the bottom of the screen: categories, and above them the tools
/// of the open category.
struct BuildToolbarView: View {
    let viewModel: GameViewModel
    @State private var openCategory: ToolCategory?

    var body: some View {
        VStack(spacing: 8) {
            if let openCategory {
                ToolPaletteView(viewModel: viewModel, category: openCategory)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 4) {
                ForEach(ToolCategory.allCases) { category in
                    CategoryButton(category: category, isOpen: openCategory == category) {
                        openCategory = openCategory == category ? nil : category
                    }
                }

                Divider()
                    .frame(height: 28)
                    .padding(.horizontal, 4)

                ControlsHelpButton()
            }
            .padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .animation(.easeOut(duration: 0.15), value: openCategory)
        .onChange(of: viewModel.selectedTool) { _, tool in
            // Keep the palette of the active tool open, e.g. after a keyboard shortcut.
            if let tool {
                openCategory = ToolCategory.of(tool, in: viewModel.catalog)
            }
        }
    }
}

private struct CategoryButton: View {
    let category: ToolCategory
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: category.symbol)
                    .font(.system(size: 16))
                Text(category.title)
                    .font(.caption2)
            }
            .frame(width: 76, height: 44)
            .background(isOpen ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(category.shortcut), modifiers: [])
        .help(Text(verbatim: "\(category.title) (\(category.shortcut))"))
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }
}

private struct ToolPaletteView: View {
    let viewModel: GameViewModel
    let category: ToolCategory

    var body: some View {
        HStack(spacing: 6) {
            ForEach(category.tools(in: viewModel.catalog), id: \.self) { tool in
                ToolCard(
                    presentation: ToolPresentation(tool, catalog: viewModel.catalog),
                    isSelected: viewModel.selectedTool == tool,
                    action: { viewModel.toggleTool(tool) }
                )
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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
            detail = String(localized: "Drag to build. \(catalog.rules.roadCostPerCell) thalers per cell.")
            costLabel = "\(catalog.rules.roadCostPerCell)"
            symbol = "road.lanes"
            color = Color(red: 0.66, green: 0.60, blue: 0.50)
        case .zone:
            name = String(localized: "Residential zone")
            detail = String(localized: "Drag to zone an area. Houses appear next to roads when the town needs them.")
            costLabel = nil
            symbol = "square.dashed.inset.filled"
            color = .green
        case .unzone:
            name = String(localized: "Remove zone")
            detail = String(localized: "Drag to remove zoning. Existing houses stay.")
            costLabel = nil
            symbol = "square.dashed"
            color = .orange
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
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(presentation.color.opacity(presentation.symbol == nil ? 1 : 0.2))
                    if let symbol = presentation.symbol {
                        Image(systemName: symbol)
                            .foregroundStyle(presentation.color)
                    }
                }
                .frame(width: 34, height: 26)

                Text(presentation.name)
                    .font(.caption)
                    .lineLimit(1)
                if let costLabel = presentation.costLabel {
                    Text(verbatim: costLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 92, height: 74)
            .background(isSelected ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(presentation.detail)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Small popover with the mouse and keyboard controls.
private struct ControlsHelpButton: View {
    @State private var isShown = false

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 16))
                .frame(width: 36, height: 44)
        }
        .buttonStyle(.plain)
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
