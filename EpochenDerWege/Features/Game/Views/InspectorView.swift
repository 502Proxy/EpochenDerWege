import SwiftUI

/// Details of the selected building.
struct InspectorView: View {
    let details: BuildingDetails
    let onDemolish: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(details.name)
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(toneColor)
                    .frame(width: 8, height: 8)
                Text(details.status)
                    .font(.callout)
            }

            Divider()

            ForEach(details.rows) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(row.value)
                        .monospacedDigit()
                }
                .font(.callout)
            }

            Divider()

            Button(role: .destructive, action: onDemolish) {
                Label("Demolish", systemImage: "trash")
            }
            .help(Text("Half of the cost is refunded."))
        }
        .frame(width: 280)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var toneColor: Color {
        switch details.tone {
        case .good: .green
        case .warning: .orange
        case .problem: .red
        case .neutral: .secondary
        }
    }
}

/// A short message at the bottom of the screen.
struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
    }
}
