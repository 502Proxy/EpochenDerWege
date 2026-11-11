import GameDomain
import SwiftUI

/// Details of the selected building.
struct InspectorView: View {
    let details: BuildingDetails
    let onDemolish: () -> Void
    let onClose: () -> Void
    var onPause: (Bool) -> Void = { _ in }
    var onPriority: (DeliveryPriority) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(Text(details.name), symbol: "info.circle", onClose: onClose)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(GameTheme.color(of: details.tone))
                        .frame(width: 8, height: 8)
                    Text(details.status)
                        .font(GameTheme.body)
                }

                Divider()

                ForEach(details.rows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label)
                            .foregroundStyle(GameTheme.secondaryText)
                        Spacer(minLength: 12)
                        Text(row.value)
                            .monospacedDigit()
                    }
                    .font(GameTheme.body)
                }

                if details.isConfigurable {
                    Divider()
                    Toggle("Paused", isOn: Binding(get: { details.isPaused }, set: onPause))
                        .help(Text("A paused building does no work, releases its workers and receives no deliveries."))
                    Picker("Delivery priority", selection: Binding(get: { details.priority }, set: onPriority)) {
                        ForEach(DeliveryPriority.allCases, id: \.self) { priority in
                            Text(GameText.name(of: priority)).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help(Text("Carriers serve buildings with high priority first."))
                }

                Divider()

                Button(role: .destructive, action: onDemolish) {
                    Label("Demolish", systemImage: "trash")
                        .foregroundStyle(GameTheme.negative)
                }
                .help(Text("Half of the cost is refunded."))
            }
            .padding(14)
        }
        .frame(width: 290)
        .clipShape(RoundedRectangle(cornerRadius: GameTheme.cornerRadius))
        .gamePanel()
    }
}
