import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query private var settingsList: [BudgetSettings]
    @State private var monthKey = MonthKey.key(for: .now)

    private var settings: BudgetSettings? { settingsList.first }
    private var calc: BudgetCalculator { BudgetCalculator(expenses: expenses, settings: settings) }

    /// Plan months up to the current one.
    private var availableMonths: [String] {
        let current = MonthKey.key(for: .now)
        let months = (settings?.planMonths ?? [current]).filter { $0 <= current }
        return months.isEmpty ? [current] : months
    }

    private var monthExpenses: [Expense] {
        expenses.filter { MonthKey.key(for: $0.date) == monthKey }
    }

    /// The last day to show: today for the current month, the month's last day otherwise.
    private var lastDay: Date {
        if monthKey == MonthKey.key(for: .now) { return .now }
        let first = MonthKey.firstDay(of: monthKey) ?? .now
        let next = Calendar.current.date(byAdding: .month, value: 1, to: first) ?? first
        return next.addingTimeInterval(-1)
    }

    private struct CategoryTotal: Identifiable {
        let category: Category
        let cents: Int
        var id: String { category.rawValue }
    }

    private var categoryTotals: [CategoryTotal] {
        var totals: [Category: Int] = [:]
        for e in monthExpenses { totals[e.category, default: 0] += e.amountCents }
        return totals.map { CategoryTotal(category: $0.key, cents: $0.value) }.sorted { $0.cents > $1.cents }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack(alignment: .bottom) {
                        ScreenHeader(caption: monthCaption, title: "History")
                        monthSwitcher
                    }
                    totalsCard
                    daysList
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .background(GlowBackground())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Date.self) { day in
                DayDetailView(day: day)
            }
        }
    }

    private var monthCaption: String {
        guard let d = MonthKey.firstDay(of: monthKey) else { return monthKey }
        return d.formatted(.dateTime.month(.wide).year())
    }

    private var monthSwitcher: some View {
        let i = availableMonths.firstIndex(of: monthKey) ?? 0
        return HStack(spacing: 4) {
            Button { monthKey = availableMonths[i - 1] } label: {
                Image(systemName: "chevron.left").frame(width: 40, height: 40)
            }
            .disabled(i == 0)
            .accessibilityLabel("Previous month")
            Button { monthKey = availableMonths[i + 1] } label: {
                Image(systemName: "chevron.right").frame(width: 40, height: 40)
            }
            .disabled(i >= availableMonths.count - 1)
            .accessibilityLabel("Next month")
        }
        .font(.system(size: 15, weight: .bold))
        .padding(2)
        .glassCard(radius: 22)
    }

    private var totalsCard: some View {
        let total = monthExpenses.reduce(0) { $0 + $1.amountCents }
        let maxValue = max(1, categoryTotals.first?.cents ?? 1)
        return VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Spent this month").font(.subheadline.weight(.semibold))
                Spacer()
                Text(Money.format(total, alwaysShowCents: true)).font(Theme.rounded(26))
            }
            if categoryTotals.isEmpty {
                Text("No expenses this month yet.").font(.footnote).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(categoryTotals) { item in
                let cat = item.category
                let cents = item.cents
                HStack(spacing: 10) {
                    Text(cat.title).font(.footnote).foregroundStyle(.white.opacity(0.85))
                        .frame(width: 82, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(cat.color)
                                .frame(width: max(6, geo.size.width * CGFloat(cents) / CGFloat(maxValue)))
                        }
                    }
                    .frame(height: 10)
                    Text(Money.format(cents, alwaysShowCents: true)).font(Theme.rounded(13))
                        .frame(width: 56, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .glassCard(radius: 28)
    }

    private var daysList: some View {
        VStack(spacing: 10) {
            ForEach(calc.daySummaries(inMonthOf: lastDay)) { day in
                let dayItems = monthExpenses.filter { Calendar.current.isDate($0.date, inSameDayAs: day.day) }
                NavigationLink(value: day.day) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                .font(.subheadline.weight(.bold))
                            Text(dayItems.isEmpty ? "No expenses" : categoriesText(dayItems))
                                .font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(Money.format(day.spentCents, alwaysShowCents: true)).font(Theme.rounded(17))
                            StatusBadge(isOver: day.isOver, overBy: day.spentCents - day.limitCents)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .glassCard(radius: 22)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func categoriesText(_ items: [Expense]) -> String {
        var seen: [Category] = []
        for e in items where !seen.contains(e.category) { seen.append(e.category) }
        return seen.map(\.title).joined(separator: ", ")
    }
}

struct StatusBadge: View {
    let isOver: Bool
    let overBy: Int

    var body: some View {
        Text(isOver ? "Over \(Money.format(overBy, alwaysShowCents: true))" : "Under")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .foregroundStyle(isOver ? Color(hex: 0xFFC9AE) : Color(hex: 0xB6FFCB))
            .background((isOver ? Color(hex: 0xFF8C5A).opacity(0.28) : Theme.mint.opacity(0.22)), in: Capsule())
    }
}

/// All expenses of one day; swipe to delete, tap to edit.
struct DayDetailView: View {
    let day: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var editing: Expense?

    private var items: [Expense] {
        expenses.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    var body: some View {
        List {
            ForEach(items) { e in
                Button { editing = e } label: { ExpenseRow(expense: e) }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.white.opacity(0.06))
            }
            .onDelete { offsets in
                for i in offsets { context.delete(items[i]) }
            }
            if items.isEmpty {
                Text("No expenses on this day.").foregroundStyle(Theme.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(GlowBackground())
        .navigationTitle(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 90) }
        .sheet(item: $editing) { e in
            AddExpenseView(editing: e)
                .presentationBackground(Theme.base)
        }
    }
}
