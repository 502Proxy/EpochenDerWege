import SwiftUI

/// A window inside the game: dark panel with a title bar that can be dragged.
///
/// Clicking or dragging a panel brings it to the front. Its position is kept by the
/// caller, so a panel reopens where the player left it.
struct FloatingPanelView<Content: View>: View {
    let panel: GamePanel
    @Binding var offset: CGSize
    let onClose: () -> Void
    let onFocus: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var dragStart: CGSize?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(Text(GameText.title(of: panel)), symbol: panel.symbol, onClose: onClose)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(coordinateSpace: .global)
                        .onChanged { value in
                            if dragStart == nil {
                                dragStart = offset
                                onFocus()
                            }
                            let start = dragStart ?? .zero
                            offset = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .pointerStyle(.grabIdle)

            content()
                .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: GameTheme.cornerRadius))
        .gamePanel()
        .simultaneousGesture(TapGesture().onEnded(onFocus))
        .offset(offset)
    }
}
