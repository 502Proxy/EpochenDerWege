import SwiftUI

struct ContentView: View {
    @State private var controller = GameController()

    var body: some View {
        ZStack(alignment: .top) {
            GameView(controller: controller)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TopBar(controller: controller)

                HStack(alignment: .top) {
                    BuildMenu(controller: controller)
                    Spacer()
                    if let info = controller.inspector {
                        InspectorPanel(
                            info: info,
                            onDemolish: { controller.demolishSelected() },
                            onClose: { controller.select(buildingID: nil) }
                        )
                    }
                }
                .padding(12)

                Spacer()

                if let message = controller.message {
                    Text(message)
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 16)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: controller.message)
        }
    }
}
