import SwiftUI

/// The month at a glance: one square per day, green when you stayed within that day's limit,
/// red when you went over. Tap a day to open it.
struct MonthCalendarCard: View {
    let month: Date
    /// Days with a result (from the first day you used the app up to today).
    let days: [BudgetCalculator.DaySummary]

    private var calendar: Calendar {
        var c = Calendar.current
        c.locale = AppLanguage.locale
        return c
    }

    /// Leading blanks then each day of the month.
    private var cells: [Date?] {
        let cal = calendar
        guard let interval = cal.dateInterval(of: .month, for: month),
              let count = cal.range(of: .day, in: .month, for: month)?.count else { return [] }
        let weekday = cal.component(.weekday, from: interval.start)
        let blanks = (weekday - cal.firstWeekday + 7) % 7
        let dates = (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: interval.start) }
        return Array(repeating: nil, count: blanks) + dates.map { Optional($0) }
    }

    private var weekdayLetters: [String] {
        let cal = calendar
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(cal.firstWeekday - 1 + $0) % 7] }
    }

    var body: some View {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let onBudget = days.filter { !$0.isOver }.count
        let over = days.count - onBudget
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("At a glance").font(.headline)
                Spacer()
                Text("\(onBudget) on budget · \(over) over")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdayLetters.enumerated()), id: \.offset) { _, letter in
                    Text(letter).font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        cell(date, byDay[calendar.startOfDay(for: date)])
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
            HStack(spacing: 14) {
                legend(Theme.mint, "On budget")
                legend(Theme.warn, "Over")
            }
        }
        .padding(16)
        .glassCard()
    }

    @ViewBuilder
    private func cell(_ date: Date, _ summary: BudgetCalculator.DaySummary?) -> some View {
        let number = Text(date.formatted(.dateTime.day().locale(AppLanguage.locale)))
            .font(.system(size: 14, weight: calendar.isDateInToday(date) ? .bold : .regular, design: .serif))
            .frame(maxWidth: .infinity, minHeight: 38)
        if let summary {
            let color = summary.isOver ? Theme.warn : Theme.mint
            NavigationLink(value: summary.day) {
                number
                    .foregroundStyle(summary.isOver ? Theme.base : Theme.ink)
                    .background(summary.isOver ? color : color.opacity(0.34), in: Theme.chipShape)
                    .overlay {
                        if calendar.isDateInToday(date) {
                            Theme.chipShape.strokeBorder(Theme.highlight, lineWidth: 2)
                        }
                    }
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("\(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.locale))), \(summary.isOver ? String(localized: "Over", bundle: AppLanguage.bundle) : String(localized: "On budget", bundle: AppLanguage.bundle))")
        } else {
            number.foregroundStyle(Theme.secondary.opacity(0.6))
        }
    }

    private func legend(_ color: Color, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Theme.chipShape.fill(color).frame(width: 10, height: 10)
            Text(title).font(.caption2).foregroundStyle(Theme.secondary)
        }
    }
}
