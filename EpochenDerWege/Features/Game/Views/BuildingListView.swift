import GameDomain
import SwiftUI

/// Every building with its state; selecting one moves the camera there.
struct BuildingListView: View {
    let viewModel: GameViewModel

    @State private var filter = Filter.all
    @State private var sortOrder = [KeyPathComparator(\BuildingRow.name)]
    @State private var selection: BuildingID?

    enum Filter: Hashable, CaseIterable {
        case all, production, commerce, housing, logistics

        var title: LocalizedStringKey {
            switch self {
            case .all: "All"
            case .production: "Production"
            case .commerce: "Markets and workshops"
            case .housing: "Houses"
            case .logistics: "Storehouses and stops"
            }
        }

        func includes(_ category: BuildingCategory) -> Bool {
            switch self {
            case .all: true
            case .production: category == .production
            case .commerce: category == .commerce
            case .housing: category == .housing
            case .logistics: category == .storage || category == .stop
            }
        }
    }

    private var rows: [BuildingRow] {
        viewModel.buildingRows.filter { filter.includes($0.category) }.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Show", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .frame(width: 300)

            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Building", value: \.name)
                TableColumn("Status", value: \.status) { row in
                    HStack(spacing: 6) {
                        Circle().fill(row.tone.color).frame(width: 8, height: 8)
                        Text(row.status)
                    }
                }
                TableColumn("Workers", value: \.workers)
                TableColumn("Efficiency", value: \.efficiencySortKey) { row in
                    if let efficiency = row.efficiency {
                        Text(GameText.percent(efficiency)).monospacedDigit()
                    }
                }
            }
            .onChange(of: selection) { _, id in
                if let id {
                    viewModel.focus(on: id)
                }
            }

            Text("Select a building to jump to it.")
                .font(.caption)
                .foregroundStyle(GameTheme.secondaryText)
        }
        .frame(width: 640, height: 400)
    }
}

extension StatusTone {
    var color: Color {
        GameTheme.color(of: self)
    }
}
