import Charts
import GameDomain
import SwiftUI

/// The finance window: overview by category, sales per good, costs per type and the
/// balance over time.
struct FinanceView: View {
    let summary: FinanceSummary
    let onClose: () -> Void

    @State private var tab = Tab.overview

    enum Tab: Hashable {
        case overview, sales, costs, balance
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Finances")
                    .font(.title2.bold())
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }

            Picker("View", selection: $tab) {
                Text("Overview").tag(Tab.overview)
                Text("Sales by good").tag(Tab.sales)
                Text("Costs by type").tag(Tab.costs)
                Text("Balance").tag(Tab.balance)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                switch tab {
                case .overview:
                    overview
                case .sales:
                    breakdown(summary.salesByGood, empty: "No sales yet. Draw commercial or industrial zones so towns build markets and workshops.")
                case .costs:
                    breakdown(summary.costsByType, empty: "No costs yet.")
                case .balance:
                    balanceChart
                }
            }
        }
        .padding(20)
        .frame(width: 640, height: 520)
    }

    // MARK: - Tabs

    private var overview: some View {
        Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 6) {
            header
            sectionTitle("Income")
            ForEach(summary.income) { row($0) }
            sectionTitle("Expenses")
            ForEach(summary.expenses) { row($0) }
            Divider().gridCellUnsizedAxes(.horizontal)
            GridRow {
                Text("Profit").bold().gridColumnAlignment(.leading)
                amountCells(summary.profit, bold: true)
            }
        }
    }

    private func breakdown(_ rows: [FinanceSummary.Row], empty: LocalizedStringKey) -> some View {
        Group {
            if rows.isEmpty {
                Text(empty)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 6) {
                    header
                    ForEach(rows) { row($0) }
                }
            }
        }
    }

    private var balanceChart: some View {
        Group {
            if summary.history.count > 1 {
                Chart(summary.history) { point in
                    AreaMark(x: .value("Year", point.year), y: .value("Balance", point.balance))
                        .foregroundStyle(.linearGradient(colors: [.accentColor.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Year", point.year), y: .value("Balance", point.balance))
                        .interpolationMethod(.monotone)
                }
                .chartXAxisLabel("Year")
                .chartYAxisLabel("Thalers")
                .frame(height: 360)
            } else {
                Text("The balance chart fills up as days pass.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Building blocks

    private var header: some View {
        GridRow {
            Text(verbatim: "").gridColumnAlignment(.leading)
            Text("Month \(summary.displayMonth)").font(.caption.bold())
            Text("Previous month").font(.caption.bold())
            Text("Year \(summary.displayYear)").font(.caption.bold())
            Text("Year \(summary.displayYear - 1)").font(.caption.bold())
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        GridRow {
            Text(title)
                .font(.headline)
                .gridCellColumns(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        }
    }

    private func row(_ row: FinanceSummary.Row) -> some View {
        GridRow {
            Text(row.title)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            amountCells(row.amounts, bold: false)
        }
    }

    @ViewBuilder
    private func amountCells(_ amounts: FinanceSummary.Amounts, bold: Bool) -> some View {
        amount(amounts.thisMonth, bold: bold)
        amount(amounts.lastMonth, bold: bold)
        amount(amounts.thisYear, bold: bold)
        amount(amounts.lastYear, bold: bold)
    }

    private func amount(_ value: Int, bold: Bool) -> some View {
        Text(value, format: .number.sign(strategy: .always(includingZero: false)))
            .monospacedDigit()
            .fontWeight(bold ? .bold : .regular)
            .foregroundStyle(value > 0 ? Color.green : value < 0 ? Color.red : Color.secondary)
    }
}
