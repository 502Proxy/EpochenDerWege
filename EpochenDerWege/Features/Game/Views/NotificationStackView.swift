import SwiftUI

/// Recent messages in the top right corner. New ones slide in, old ones fade out.
struct NotificationStackView: View {
    let notifications: [GameNotification]
    let onDismiss: (Int) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(notifications) { notification in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: notification.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GameTheme.color(of: notification.tone))
                        .frame(width: 18)
                    Text(notification.text)
                        .font(GameTheme.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(width: 320, alignment: .leading)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(GameTheme.color(of: notification.tone))
                        .frame(width: 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .gamePanel(cornerRadius: 8)
                .onTapGesture { onDismiss(notification.id) }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: notifications.map(\.id))
    }
}
