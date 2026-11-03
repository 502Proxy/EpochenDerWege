import SwiftUI

/// The main window: 3D scene with the HUD on top.
struct GameScreen: View {
    let session: GameSession

    private var viewModel: GameViewModel { session.viewModel }

    var body: some View {
        ZStack(alignment: .top) {
            SceneView(viewModel: viewModel, engine: session.engine)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TopBarView(viewModel: viewModel)

                HStack(alignment: .top) {
                    Spacer()
                    if let details = viewModel.inspector {
                        InspectorView(
                            details: details,
                            onDemolish: viewModel.demolishSelected,
                            onClose: { viewModel.selectBuilding(nil) },
                            onPause: { viewModel.setPaused($0, building: details.id) },
                            onPriority: { viewModel.setPriority($0, building: details.id) }
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(12)

                Spacer()

                if let toast = viewModel.toast {
                    ToastView(text: toast.text)
                        .id(toast.id)
                        .transition(.opacity)
                        .padding(.bottom, 8)
                }

                if viewModel.selectedTool == .line {
                    PendingLineBar(viewModel: viewModel)
                        .padding(.bottom, 8)
                }

                BuildToolbarView(viewModel: viewModel)
                    .padding(.bottom, 14)
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.toast)
            .animation(.easeInOut(duration: 0.2), value: viewModel.inspector?.id)
        }
        .task {
            await viewModel.run()
        }
    }
}
