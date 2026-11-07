import SwiftUI
import Charts

/// Everyday spending per month as bars, with the month's living money as a line, and the average per day.
struct TrendCard: View {
    let months: [BudgetCalculator.MonthSpending]
    let budget: (String) -> Int
    let currentMonth: String

    private var shown: [BudgetCalculator.MonthSpending] { months.filter { $0.monthKey <= currentMonth } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Everyday spending").font(.subheadline.weight(.semibold))
                Spacer()
                if let avg = averagePerFinishedMonth {
                    Text("Avg \(Money.format(avg)) / month").font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            Chart {
                ForEach(shown) { m in
                    let title = MonthKey.title(of: m.monthKey).prefix(3).description
                    BarMark(x: .value("Month", title), y: .value("Spent", Double(m.livingCents) / 100))
                        .foregroundStyle(m.livingCents > budget(m.monthKey) ? Theme.warn : Theme.mint)
                        .cornerRadius(6)
                    // A short marker per month (a line would need two months to show).
                    RectangleMark(x: .value("Month", title), y: .value("Living money", Double(budget(m.monthKey)) / 100),
                                  width: .ratio(0.9), height: 2)
                        .foregroundStyle(Theme.ink.opacity(0.7))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Theme.ink.opacity(0.1))
                    AxisValueLabel { if let v = value.as(Double.self) { Text(verbatim: "$\(Int(v))") } }
                        .foregroundStyle(Theme.secondary)
                }
            }
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.secondary) }
            }
            .frame(height: 150)
            HStack(spacing: 14) {
                legend(Theme.mint, "Spent")
                legend(Theme.warn, "Over")
                HStack(spacing: 5) {
                    Rectangle().fill(Theme.ink.opacity(0.6)).frame(width: 14, height: 2)
                    Text("Living money").font(.caption2).foregroundStyle(Theme.secondary)
                }
            }
        }
        .padding(16)
        .glassCard(radius: 26)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Everyday spending by month"))
    }

    private var averagePerFinishedMonth: Int? {
        let finished = shown.filter { $0.monthKey < currentMonth }
        guard !finished.isEmpty else { return nil }
        return finished.reduce(0) { $0 + $1.livingCents } / finished.count
    }

    private func legend(_ color: Color, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text).font(.caption2).foregroundStyle(Theme.secondary)
        }
    }
}
