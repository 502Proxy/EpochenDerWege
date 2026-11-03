import GameDomain
import SwiftUI

/// Building palette on the left: choose a building, then click on the map.
struct BuildMenuView: View {
    let viewModel: GameViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Build")
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(viewModel.catalog.buildings) { definition in
                BuildMenuRow(
                    definition: definition,
                    isSelected: viewModel.selectedTool == definition.id,
                    summary: GameText.summary(of: definition, catalog: viewModel.catalog),
                    action: { viewModel.toggleTool(definition.id) }
                )
            }

            Divider()
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text("Click: build or select")
                Text("Drag: move the map")
                Text("Right-drag: rotate")
                Text("Scroll: zoom")
                Text("Right-click or Esc: cancel")
                Text("WASD, Q/E, Space")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(width: 220)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct BuildMenuRow: View {
    let definition: BuildingDefinition
    let isSelected: Bool
    let summary: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(definition.color))
                    .frame(width: 12, height: 12)
                Text(GameText.name(of: definition))
                Spacer()
                Text(definition.cost, format: .number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(
                isSelected ? Color.accentColor.opacity(0.25) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(summary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension Color {
    init(_ color: GameColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue)
    }
}
