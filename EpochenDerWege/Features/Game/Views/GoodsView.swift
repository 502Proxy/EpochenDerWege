import GameDomain
import SwiftUI

/// Production, consumption, stock and sales per good.
struct GoodsView: View {
    let goods: [GoodRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Table(goods) {
                TableColumn("Good") { row in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(row.color))
                            .frame(width: 10, height: 10)
                        Text(row.name)
                    }
                }
                TableColumn("Produced") { row in number(row.producedThisYear) }
                TableColumn("Consumed") { row in number(row.consumedThisYear) }
                TableColumn("Net") { row in
                    Text(row.balanceThisYear, format: .number.sign(strategy: .always(includingZero: false)))
                        .monospacedDigit()
                        .foregroundStyle(row.balanceThisYear < 0 ? GameTheme.negative : row.balanceThisYear > 0 ? GameTheme.positive : GameTheme.secondaryText)
                }
                TableColumn("In stock") { row in number(row.inStock) }
                TableColumn("Sales") { row in number(row.salesThisYear) }
                TableColumn("Last year") { row in
                    Text(verbatim: "+\(row.producedLastYear) / −\(row.consumedLastYear)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Text("Figures for the current year. Net = produced − consumed; a negative value means the economy uses more than it makes.")
                .font(.caption)
                .foregroundStyle(GameTheme.secondaryText)
        }
        .frame(width: 700, height: 360)
    }

    private func number(_ value: Int) -> some View {
        Text(value, format: .number)
            .monospacedDigit()
    }
}
