import Charts
import GameDomain
import SwiftUI

/// Income and expenses by category for this and last year, and the balance over time.
struct FinanceView: View {
    let summary: FinanceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Finances")
                .font(.title3.bold())

            Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    Text(verbatim: "").gridColumnAlignment(.leading)
                    Text("Year \(summary.displayYear)").font(.caption.bold())
                    Text("Year \(summary.displayYear - 1)").font(.caption.bold())
                }

                section("Income", rows: summary.income)
                section("Expenses", rows: summary.expenses)

                Divider().gridCellUnsizedAxes(.horizontal)

                GridRow {
                    Text("Profit").bold().gridColumnAlignment(.leading)
                    amount(summary.currentProfit).bold()
                    amount(summary.previousProfit).bold()
                }
            }

            if summary.history.count > 1 {
                Text("Balance")
                    .font(.headline)
                Chart(summary.history) { point in
                    LineMark(
                        x: .value("Year", point.year),
                        y: .value("Balance", point.balance)
                    )
                    .interpolationMethod(.monotone)
                    AreaMark(
                        x: .value("Year", point.year),
                        y: .value("Balance", point.balance)
                    )
                    .foregroundStyle(.linearGradient(colors: [.accentColor.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                }
                .chartXAxisLabel("Year")
                .frame(height: 160)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, rows: [FinanceSummary.Row]) -> some View {
        GridRow {
            Text(title)
                .font(.headline)
                .gridCellColumns(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
        ForEach(rows) { row in
            GridRow {
                Text(GameText.name(of: row.category)).foregroundStyle(.secondary)
                amount(row.currentYear)
                amount(row.previousYear)
            }
        }
    }

    private func amount(_ value: Int) -> some View {
        Text(value, format: .number.sign(strategy: .always(includingZero: false)))
            .monospacedDigit()
            .foregroundStyle(value > 0 ? Color.green : value < 0 ? Color.red : Color.secondary)
    }
}
