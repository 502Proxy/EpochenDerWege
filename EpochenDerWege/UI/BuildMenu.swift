import Simulation
import SwiftUI

/// Baumenü links: Gebäude wählen, dann auf die Karte klicken.
struct BuildMenu: View {
    @Bindable var controller: GameController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bauen")
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(controller.buildingDefinitions) { definition in
                let selected = controller.selectedTool == definition.id
                Button {
                    controller.toggleTool(definition.id)
                } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(rgb: definition.color))
                            .frame(width: 12, height: 12)
                        Text(definition.name)
                        Spacer()
                        Text("\(definition.cost)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(
                        selected ? Color.accentColor.opacity(0.25) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(description(of: definition))
            }

            Divider()
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text("Linksklick: bauen / auswählen")
                Text("Ziehen: Karte verschieben")
                Text("Rechts ziehen: drehen")
                Text("Scrollen: zoomen")
                Text("Rechtsklick / Esc: abwählen")
                Text("WASD, Q/E, Leertaste")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(width: 210)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func description(of definition: BuildingDefinition) -> String {
        let data = controller.simulation.data
        var parts: [String] = []
        if !definition.inputs.isEmpty {
            let list = definition.inputs.sorted { $0.key < $1.key }.map { "\($0.value) \(data.goodName($0.key))" }
            parts.append("Braucht " + list.joined(separator: ", "))
        }
        if !definition.outputs.isEmpty {
            let list = definition.outputs.sorted { $0.key < $1.key }.map { "\($0.value) \(data.goodName($0.key))" }
            parts.append("Erzeugt " + list.joined(separator: ", ") + " in \(Int(definition.cycleDays)) Tagen")
        }
        if definition.workers > 0 {
            parts.append("\(definition.workers) Arbeiter")
        }
        if let resource = definition.resource {
            parts.append("Braucht \(resource.biome.germanName) in der Nähe")
        }
        if definition.residents > 0 {
            parts.append("Bis zu \(definition.residents) Bewohner")
        }
        return parts.joined(separator: " · ")
    }
}

extension Color {
    init(rgb: [Double]) {
        if rgb.count >= 3 {
            self.init(.sRGB, red: rgb[0], green: rgb[1], blue: rgb[2])
        } else {
            self = .gray
        }
    }
}
