import SwiftUI

/// Obere Leiste: Datum, Geld, Bevölkerung, Lagerbestand und Spielgeschwindigkeit.
struct TopBar: View {
    @Bindable var controller: GameController

    var body: some View {
        let hud = controller.hud
        HStack(spacing: 16) {
            Text("Epochen der Wege")
                .font(.headline)

            Divider().frame(height: 18)

            stat("calendar", "Jahr \(hud.year + 1), Tag \(hud.dayOfYear + 1)")
            stat("banknote", "\(hud.money) Taler")
            stat("person.3.fill", "\(hud.population) Einwohner")
            stat("hammer.fill", "Arbeiter \(hud.workersAssigned)/\(hud.workersNeeded)")
                .help("\(hud.freeWorkers) Bewohner ohne Arbeit")
            stat("figure.walk", "\(hud.carriers) Träger")

            Divider().frame(height: 18)

            HStack(spacing: 10) {
                ForEach(hud.stock, id: \.name) { item in
                    Text("\(item.name) \(item.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .help("Bestand in allen Lagerhäusern")

            Spacer()

            Picker("Geschwindigkeit", selection: $controller.speed) {
                Image(systemName: "pause.fill").tag(0)
                Text("1×").tag(1)
                Text("2×").tag(2)
                Text("4×").tag(4)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)
            .help("Leertaste: Pause")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func stat(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.callout.monospacedDigit())
            .lineLimit(1)
    }
}
