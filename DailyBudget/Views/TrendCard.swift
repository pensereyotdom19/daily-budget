import SwiftUI
import Charts

/// This month, day by day: one bar per day for everyday spending (red when over that day's
/// limit), a dashed step line for each day's limit, and the average spent per day so far.
/// Days still to come show as an empty axis, so the month's shape is clear from the 1st.
struct TrendCard: View {
    /// Days of this month up to today (any order).
    let days: [BudgetCalculator.DaySummary]
    let month: Date

    private var calendar: Calendar { .current }
    private var dayCount: Int { calendar.range(of: .day, in: .month, for: month)?.count ?? 30 }
    private var sorted: [BudgetCalculator.DaySummary] { days.sorted { $0.day < $1.day } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(month.formatted(.dateTime.month(.wide).locale(AppLanguage.locale))), day by day")
                    .font(.headline)
                Spacer()
                if let avg = averagePerDay {
                    Text("Avg \(Money.format(avg, alwaysShowCents: true)) / day")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            Chart {
                ForEach(sorted) { d in
                    let n = calendar.component(.day, from: d.day)
                    BarMark(x: .value("Day", n), y: .value("Spent", Double(d.spentCents) / 100), width: .fixed(6))
                        .foregroundStyle(d.isOver ? Theme.warn : Theme.mint)
                        .cornerRadius(2)
                    LineMark(x: .value("Day", n), y: .value("Limit", Double(d.limitCents) / 100))
                        .interpolationMethod(.stepCenter)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .chartXScale(domain: 0.5...(Double(dayCount) + 0.5))
            .chartXAxis {
                AxisMarks(values: [1, 8, 15, 22, 29]) { value in
                    AxisValueLabel { if let v = value.as(Int.self) { Text(verbatim: "\(v)") } }
                        .foregroundStyle(Theme.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.rule)
                    AxisValueLabel { if let v = value.as(Double.self) { Text(verbatim: "$\(Int(v))") } }
                        .foregroundStyle(Theme.secondary)
                }
            }
            .frame(height: 140)
            HStack(spacing: 14) {
                legend(Theme.mint, "Spent")
                legend(Theme.warn, "Over")
                HStack(spacing: 5) {
                    Rectangle().fill(Theme.secondary).frame(width: 14, height: 1)
                    Text("Daily limit").font(.caption2).foregroundStyle(Theme.secondary)
                }
            }
        }
        .padding(16)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Everyday spending each day this month"))
    }

    private var averagePerDay: Int? {
        guard !days.isEmpty else { return nil }
        return days.reduce(0) { $0 + $1.spentCents } / days.count
    }

    private func legend(_ color: Color, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(text).font(.caption2).foregroundStyle(Theme.secondary)
        }
    }
}
