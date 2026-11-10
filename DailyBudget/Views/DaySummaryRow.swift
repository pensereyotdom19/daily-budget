import SwiftUI

/// One day: a one-line summary (spent of that day's limit); tap to show its expenses underneath.
/// Used by History's "day by day" and by each month's screen.
struct DaySummaryRow: View {
    let day: BudgetCalculator.DaySummary
    let items: [Expense]
    /// Extra income received that day (shown in green; it doesn't count as spending).
    var incomes: [Income] = []
    let isOpen: Bool
    let toggle: () -> Void

    private var everyday: [Expense] { items.filter { $0.category.countsAsLiving }.sorted { $0.date < $1.date } }
    private var other: [Expense] { items.filter { !$0.category.countsAsLiving }.sorted { $0.date < $1.date } }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(items.isEmpty ? Theme.ink.opacity(0.25) : day.isOver ? Theme.warn : Theme.mint)
                        .frame(width: 8, height: 8)
                    Text(day.day.formatted(.dateTime.weekday(.abbreviated).day().locale(AppLanguage.locale)))
                        .font(.subheadline.weight(.semibold))
                    if !other.isEmpty {
                        Image(systemName: "doc.text.fill").font(.caption2).foregroundStyle(Category.bills.color)
                            .accessibilityLabel(Text("Bills paid"))
                    }
                    if !incomes.isEmpty {
                        Text("+\(Money.format(incomes.reduce(0) { $0 + $1.amountCents }))")
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.mint)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.mint.opacity(0.14), in: Theme.chipShape)
                            .accessibilityLabel(Text("Extra money"))
                    }
                    Spacer()
                    Text(Money.format(day.spentCents, alwaysShowCents: true))
                        .font(Theme.rounded(16))
                        .foregroundStyle(day.isOver ? Theme.warn : Theme.ink)
                    Text("of \(Money.format(day.limitCents, alwaysShowCents: true))")
                        .font(.caption2).foregroundStyle(Theme.secondary)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold)).foregroundStyle(Theme.secondary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityHint(Text(isOpen ? "Hides this day's expenses" : "Shows this day's expenses"))

            if isOpen { details.transition(.opacity.combined(with: .move(edge: .top))) }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(incomes) { i in IncomeRow(income: i, size: 28) }
            if items.isEmpty {
                Text("Nothing spent this day.").font(.caption).foregroundStyle(Theme.secondary)
            }
            ForEach(everyday + other) { e in
                HStack(spacing: 10) {
                    ExpenseIcon(expense: e, size: 28)
                    Text(e.note.isEmpty ? e.category.title : e.note).font(.footnote.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Text(Money.format(e.amountCents, alwaysShowCents: true))
                        .font(Theme.rounded(14))
                        .foregroundStyle(e.category.countsAsLiving ? Theme.ink : Theme.secondary)
                }
            }
            HStack {
                if day.isOver {
                    Text("\(Money.format(day.spentCents - day.limitCents, alwaysShowCents: true)) over the limit")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.warn)
                } else if !items.isEmpty {
                    Text("\(Money.format(day.leftCents, alwaysShowCents: true)) under the limit")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.mint)
                }
                Spacer()
                NavigationLink(value: day.day) {
                    HStack(spacing: 3) {
                        Text("See day")
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.sky)
                }
                .buttonStyle(.pressable)
            }
            .padding(.top, 2)
        }
        .padding(.leading, 18).padding(.bottom, 12)
    }
}
