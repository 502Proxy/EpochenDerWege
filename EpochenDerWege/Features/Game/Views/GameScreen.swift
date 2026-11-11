import SwiftUI

/// The main window: the 3D map with the HUD on top.
///
/// Layout: stock at the top left, notifications at the top right, the inspector of
/// the selected building below the stock, the tool palette above the bottom bar on
/// the left, the mini map above it on the right, and floating panels in the middle.
struct GameScreen: View {
    let session: GameSession

    @State private var openCategory: ToolCategory?
    /// Where the player moved each panel; kept while the game runs.
    @State private var panelOffsets: [GamePanel: CGSize] = [:]

    private var viewModel: GameViewModel { session.viewModel }

    var body: some View {
        ZStack {
            SceneView(viewModel: viewModel, engine: session.engine)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        SettlementCard(settlement: viewModel.settlement)
                        StockStripView(stock: viewModel.hud.stock)
                        if let details = viewModel.inspector {
                            InspectorView(
                                details: details,
                                onDemolish: viewModel.demolishSelected,
                                onClose: { viewModel.selectBuilding(nil) },
                                onPause: { viewModel.setPaused($0, building: details.id) },
                                onPriority: { viewModel.setPriority($0, building: details.id) }
                            )
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                    Spacer()
                    NotificationStackView(notifications: viewModel.notifications, onDismiss: viewModel.dismissNotification)
                }
                .padding(12)

                Spacer()

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        if viewModel.selectedTool == .line {
                            PendingLineBar(viewModel: viewModel)
                        }
                        if let openCategory {
                            ToolPaletteView(viewModel: viewModel, category: openCategory)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    Spacer()
                    MiniMapView(viewModel: viewModel)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

                BottomBarView(viewModel: viewModel, openCategory: $openCategory)
            }
            .animation(.easeOut(duration: 0.15), value: openCategory)
            .animation(.easeInOut(duration: 0.2), value: viewModel.inspector?.id)

            ForEach(viewModel.openPanels) { panel in
                FloatingPanelView(
                    panel: panel,
                    offset: offsetBinding(for: panel),
                    onClose: { viewModel.closePanel(panel) },
                    onFocus: { viewModel.bringToFront(panel) }
                ) {
                    content(of: panel)
                }
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: viewModel.openPanels)
        .onChange(of: viewModel.selectedTool) { _, tool in
            // Keep the palette of the active tool open, e.g. after a keyboard shortcut.
            if let tool {
                openCategory = ToolCategory.of(tool, in: viewModel.catalog)
            }
        }
        .task {
            await viewModel.run()
        }
    }

    @ViewBuilder
    private func content(of panel: GamePanel) -> some View {
        switch panel {
        case .finances:
            FinanceView(summary: viewModel.finances)
        case .goods:
            GoodsView(goods: viewModel.goods)
        case .buildings:
            BuildingListView(viewModel: viewModel)
        case .lines:
            LinesView(viewModel: viewModel)
        }
    }

    /// Panels open slightly staggered so they do not cover each other completely.
    private func offsetBinding(for panel: GamePanel) -> Binding<CGSize> {
        let index = CGFloat(GamePanel.allCases.firstIndex(of: panel) ?? 0)
        let initial = CGSize(width: index * 28 - 40, height: index * 28 - 60)
        return Binding(
            get: { panelOffsets[panel] ?? initial },
            set: { panelOffsets[panel] = $0 }
        )
    }
}

/// Stock of all storehouses as small chips.
private struct StockStripView: View {
    let stock: [HUDState.StockItem]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(GameTheme.accent)
            if stock.isEmpty {
                Text("Storehouses are empty")
                    .font(GameTheme.caption)
                    .foregroundStyle(GameTheme.secondaryText)
            }
            ForEach(stock) { item in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(item.color))
                        .frame(width: 8, height: 8)
                    Text(verbatim: item.name)
                        .foregroundStyle(GameTheme.secondaryText)
                    Text(item.amount, format: .number)
                        .monospacedDigit()
                }
                .font(GameTheme.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .gamePanel(cornerRadius: 16)
        .help(Text("Stock in all storehouses"))
    }
}
