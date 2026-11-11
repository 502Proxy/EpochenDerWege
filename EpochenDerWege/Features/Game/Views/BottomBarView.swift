import SwiftUI

/// The bar along the bottom edge: build categories on the left, date and game speed
/// in the middle, key figures and the panel buttons on the right.
struct BottomBarView: View {
    let viewModel: GameViewModel
    @Binding var openCategory: ToolCategory?

    var body: some View {
        let hud = viewModel.hud
        HStack(spacing: 0) {
            BuildCategoryBar(openCategory: $openCategory)

            BarDivider()

            Button {
                viewModel.togglePanel(.finances)
            } label: {
                figure("banknote.fill", Text("\(hud.treasury) thalers"), tint: hud.treasury < 0 ? GameTheme.negative : GameTheme.accent)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(HUDButtonStyle(isActive: false, size: CGSize(width: 0, height: 40)))
            .help(Text("Show income and expenses (F)"))

            figure("person.3.fill", Text("\(hud.population) residents"))
                .padding(.horizontal, 8)
            figure("hammer.fill", Text("Jobs \(hud.workersEmployed)/\(hud.workersNeeded)"))
                .padding(.horizontal, 8)
                .help(Text("\(hud.unemployed) unemployed"))

            BarDivider()

            ZoneDemandView(demand: viewModel.zoneDemand) { kind in
                if viewModel.selectedTool != .zone(kind) {
                    viewModel.toggleTool(.zone(kind))
                }
            }

            Spacer(minLength: 12)

            ClockView(viewModel: viewModel)

            Spacer(minLength: 12)

            HStack(spacing: 4) {
                ForEach(GamePanel.allCases) { panel in
                    Button {
                        viewModel.togglePanel(panel)
                    } label: {
                        Image(systemName: panel.symbol)
                            .font(.system(size: 15, weight: .medium))
                    }
                    .buttonStyle(HUDButtonStyle(isActive: viewModel.isOpen(panel), size: CGSize(width: 38, height: 38)))
                    .keyboardShortcut(KeyEquivalent(panel.shortcut), modifiers: [])
                    .help(Text(verbatim: "\(GameText.title(of: panel)) (\(panel.shortcut.uppercased()))"))
                }

                BarDivider()

                OverlayMenu(viewModel: viewModel)
                ControlsHelpButton()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: GameTheme.barHeight)
        .background(GameTheme.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(GameTheme.stroke).frame(height: 1)
        }
        .foregroundStyle(GameTheme.primaryText)
        .environment(\.colorScheme, .dark)
    }

    private func figure(_ symbol: String, _ text: Text, tint: Color = GameTheme.secondaryText) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            text
                .font(GameTheme.number)
                .lineLimit(1)
        }
    }
}

/// Date and speed controls.
private struct ClockView: View {
    let viewModel: GameViewModel

    private static let speeds = [1, 2, 4]

    var body: some View {
        let hud = viewModel.hud
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 1) {
                Text("Year \(hud.year + 1)")
                    .font(GameTheme.title)
                Text("Day \(hud.dayOfYear + 1)")
                    .font(GameTheme.caption.monospacedDigit())
                    .foregroundStyle(GameTheme.secondaryText)
            }
            .frame(minWidth: 70, alignment: .trailing)

            HStack(spacing: 2) {
                Button {
                    viewModel.togglePause()
                } label: {
                    Image(systemName: viewModel.speed == 0 ? "play.fill" : "pause.fill")
                }
                .buttonStyle(HUDButtonStyle(isActive: viewModel.speed == 0, size: CGSize(width: 34, height: 32)))
                .help(Text("Space: pause"))
                .accessibilityLabel(Text("Pause"))

                ForEach(Self.speeds, id: \.self) { speed in
                    Button {
                        viewModel.setSpeed(speed)
                    } label: {
                        Text(verbatim: "\(speed)×")
                            .font(GameTheme.number.weight(.semibold))
                    }
                    .buttonStyle(HUDButtonStyle(isActive: viewModel.speed == speed, size: CGSize(width: 34, height: 32)))
                }
            }
            .padding(3)
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// Choice of the map overlay.
private struct OverlayMenu: View {
    let viewModel: GameViewModel

    var body: some View {
        Menu {
            Picker("Overlay", selection: Binding(get: { viewModel.overlay }, set: { viewModel.overlay = $0 })) {
                ForEach(MapOverlay.allCases, id: \.self) { overlay in
                    Text(GameText.name(of: overlay)).tag(overlay)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: GameTheme.smallCornerRadius)
                        .fill(viewModel.overlay == .none ? Color.clear : GameTheme.accent)
                )
                .foregroundStyle(viewModel.overlay == .none ? GameTheme.primaryText : Color.black.opacity(0.85))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("Map overlay (O)"))
    }
}
