import SwiftUI

/// Rechte Seitenleiste mit Details zum ausgewählten Gebäude.
struct InspectorPanel: View {
    let info: BuildingInfo
    let onDemolish: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(info.name)
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Label(info.status, systemImage: "circle.fill")
                .font(.callout)
                .foregroundStyle(statusColor)
                .labelStyle(StatusLabelStyle(color: statusColor))

            Divider()

            ForEach(Array(info.rows.enumerated()), id: \.offset) { _, row in
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
                Label("Abreißen (50 % zurück)", systemImage: "trash")
            }
        }
        .frame(width: 280)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var statusColor: Color {
        switch info.statusLevel {
        case .good: return .green
        case .warning: return .orange
        case .problem: return .red
        case .neutral: return .secondary
        }
    }
}

private struct StatusLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 8))
                .foregroundStyle(color)
            configuration.title
                .foregroundStyle(.primary)
        }
    }
}
