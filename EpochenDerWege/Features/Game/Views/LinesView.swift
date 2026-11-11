import GameDomain
import SwiftUI

/// All transport lines with their vehicles; buy, sell and delete.
struct LinesView: View {
    let viewModel: GameViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.lines.isEmpty {
                Text("No lines yet. Build stops next to roads, then use the line tool (key 1) to click them one after another.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(viewModel.lines) { line in
                LineRow(line: line, viewModel: viewModel)
                if line.id != viewModel.lines.last?.id {
                    Divider()
                }
            }

            if let vehicle = viewModel.catalog.vehicles.first {
                Text("\(GameText.name(of: vehicle)): \(vehicle.capacity) units, \(vehicle.price) thalers, \(vehicle.upkeepPerYear) thalers upkeep per year")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 380)
    }
}

private struct LineRow: View {
    let line: LineSummary
    let viewModel: GameViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: "\(line.number)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color(line.color), in: Circle())
                Text(line.stopNames.joined(separator: " → "))
                    .font(.callout)
                    .lineLimit(2)
                Spacer()
                Button(role: .destructive) {
                    viewModel.deleteLine(line.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(Text("Delete line"))
            }

            HStack {
                Label {
                    Text("\(line.vehicles) vehicles, \(line.cargo)/\(line.capacity) loaded")
                } icon: {
                    Image(systemName: "cart.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if line.hasRouteProblem {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(Text("A vehicle cannot reach its next stop. Check the roads."))
                }
                Spacer()
                Button {
                    viewModel.sellVehicle(of: line.id)
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(line.vehicles == 0)
                .help(Text("Sell a vehicle"))
                Button {
                    viewModel.buyVehicle(for: line.id)
                } label: {
                    Image(systemName: "plus")
                }
                .help(Text("Buy a vehicle"))
            }
        }
    }
}

/// Bar shown while the line tool is active: picked stops and the create button.
struct PendingLineBar: View {
    let viewModel: GameViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
            if viewModel.pendingLineStops.isEmpty {
                Text("Click the stops of the new line one after another.")
            } else {
                Text("New line: \(viewModel.pendingLineStops.count) stops")
            }
            Button("Create line") {
                viewModel.createPendingLine()
            }
            .disabled(viewModel.pendingLineStops.count < 2)
            .keyboardShortcut(.return, modifiers: [])
            Button("Cancel") {
                viewModel.cancelPendingLine()
            }
            .disabled(viewModel.pendingLineStops.isEmpty)
        }
        .font(GameTheme.body)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .gamePanel(cornerRadius: 20)
    }
}
