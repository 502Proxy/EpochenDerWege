import SwiftUI

/// The visual language of the in-game interface.
///
/// All HUD views take colours, shapes and metrics from here, so the look can be
/// changed in one place. The HUD is always dark: it sits on top of a bright 3D map
/// and must stay readable whatever the camera shows.
enum GameTheme {
    // MARK: Colours

    /// Panel background, slightly translucent so the map shimmers through.
    static let panel = Color(red: 0.10, green: 0.12, blue: 0.15).opacity(0.92)
    /// Raised areas inside panels: headers, selected rows, buttons.
    static let raised = Color(red: 0.17, green: 0.20, blue: 0.24)
    /// Hairline around panels and between sections.
    static let stroke = Color.white.opacity(0.10)
    /// Warm brass accent for active tools, selected tabs and highlights.
    static let accent = Color(red: 0.93, green: 0.70, blue: 0.30)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.58)
    static let positive = Color(red: 0.45, green: 0.82, blue: 0.45)
    static let negative = Color(red: 0.95, green: 0.42, blue: 0.38)
    static let warning = Color(red: 0.98, green: 0.72, blue: 0.28)

    // MARK: Metrics

    static let cornerRadius: CGFloat = 10
    static let smallCornerRadius: CGFloat = 6
    static let barHeight: CGFloat = 64

    // MARK: Type

    static let title = Font.system(.headline, design: .rounded).weight(.semibold)
    static let body = Font.system(.callout, design: .rounded)
    static let number = Font.system(.callout, design: .rounded).monospacedDigit()
    static let caption = Font.system(.caption, design: .rounded)

    static func color(of tone: StatusTone) -> Color {
        switch tone {
        case .good: positive
        case .warning: warning
        case .problem: negative
        case .neutral: secondaryText
        }
    }
}

// MARK: - Panels

private struct GamePanelModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .foregroundStyle(GameTheme.primaryText)
            .background(GameTheme.panel, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(GameTheme.stroke))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    /// Dark HUD panel with border and shadow.
    func gamePanel(cornerRadius: CGFloat = GameTheme.cornerRadius) -> some View {
        modifier(GamePanelModifier(cornerRadius: cornerRadius))
    }
}

/// Title row of a panel: icon, title, optional accessory and a close button.
struct PanelHeader<Accessory: View>: View {
    let title: Text
    let symbol: String
    let onClose: (() -> Void)?
    @ViewBuilder var accessory: () -> Accessory

    init(_ title: Text, symbol: String, onClose: (() -> Void)? = nil, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.title = title
        self.symbol = symbol
        self.onClose = onClose
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(GameTheme.accent)
            title
                .font(GameTheme.title)
                .lineLimit(1)
            Spacer(minLength: 12)
            accessory()
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(GameTheme.raised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(GameTheme.raised.opacity(0.6))
    }
}

// MARK: - Buttons

/// Square icon button of the HUD with an optional caption, highlighted when active.
struct HUDButtonStyle: ButtonStyle {
    var isActive = false
    var size = CGSize(width: 44, height: 44)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: size.width, minHeight: size.height)
            .foregroundStyle(isActive ? Color.black.opacity(0.85) : GameTheme.primaryText)
            .background(
                RoundedRectangle(cornerRadius: GameTheme.smallCornerRadius)
                    .fill(isActive ? GameTheme.accent : configuration.isPressed ? GameTheme.raised.opacity(1.4) : GameTheme.raised.opacity(0.0001))
            )
            .overlay(
                RoundedRectangle(cornerRadius: GameTheme.smallCornerRadius)
                    .strokeBorder(isActive ? .clear : GameTheme.stroke.opacity(configuration.isPressed ? 2 : 0))
            )
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Thin vertical separator between groups of the bottom bar.
struct BarDivider: View {
    var body: some View {
        Rectangle()
            .fill(GameTheme.stroke)
            .frame(width: 1, height: 36)
            .padding(.horizontal, 6)
    }
}
