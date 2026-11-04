import SwiftUI

/// Date, money, population, stock and game speed.
struct TopBarView: View {
    let viewModel: GameViewModel
    @State private var showsFinances = false
    @State private var showsLines = false

    var body: some View {
        let hud = viewModel.hud
        HStack(spacing: 16) {
            Text(verbatim: "Epochen der Wege")
                .font(.headline)

            Divider().frame(height: 18)

            stat("calendar", Text("Year \(hud.year + 1), day \(hud.dayOfYear + 1)"))
            Button {
                showsFinances.toggle()
            } label: {
                stat("banknote", Text("\(hud.treasury) thalers"))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: [])
            .help(Text("Show income and expenses (F)"))
            .sheet(isPresented: $showsFinances) {
                FinanceView(summary: viewModel.finances) { showsFinances = false }
            }
            stat("person.3.fill", Text("\(hud.population) residents"))
            stat("hammer.fill", Text("Jobs \(hud.workersEmployed)/\(hud.workersNeeded)"))
                .help(Text("\(hud.unemployed) unemployed"))
            stat("figure.walk", Text("\(hud.carriers) carriers"))
            Button {
                showsLines.toggle()
            } label: {
                stat("point.topleft.down.to.point.bottomright.curvepath", Text("\(viewModel.lines.count) lines"))
            }
            .buttonStyle(.plain)
            .help(Text("Show transport lines and vehicles"))
            .popover(isPresented: $showsLines, arrowEdge: .bottom) {
                LinesView(viewModel: viewModel)
            }

            Divider().frame(height: 18)

            HStack(spacing: 10) {
                ForEach(hud.stock) { item in
                    Text(verbatim: "\(item.name) \(item.amount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .help(Text("Stock in all storehouses"))

            Spacer()

            Picker("Speed", selection: Binding(get: { viewModel.speed }, set: { viewModel.setSpeed($0) })) {
                Image(systemName: "pause.fill")
                    .accessibilityLabel(Text("Pause"))
                    .tag(0)
                Text(verbatim: "1×").tag(1)
                Text(verbatim: "2×").tag(2)
                Text(verbatim: "4×").tag(4)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)
            .help(Text("Space: pause"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func stat(_ symbol: String, _ text: Text) -> some View {
        Label { text } icon: { Image(systemName: symbol) }
            .font(.callout.monospacedDigit())
            .lineLimit(1)
    }
}
