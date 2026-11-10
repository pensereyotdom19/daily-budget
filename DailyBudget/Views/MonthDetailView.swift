import SwiftUI
import SwiftData

/// Navigation value for opening one month, optionally filtered to one category.
struct MonthRoute: Hashable {
    let monthKey: String
    var category: Category? = nil
}

/// Everything about one month: spent vs planned, bills due (tick to pay),
/// spending by category (tap to filter) and every expense (tap to edit).
struct MonthDetailView: View {
    let monthKey: String

    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var subscriptions: [Subscription]
    @Query private var settingsList: [BudgetSettings]
    @Query(sort: \Bill.sortOrder) private var bills: [Bill]
    @State private var editing: Expense?
    /// The day opened in the list (one at a time).
    @State private var openDay: Date?
    @State private var categoryFilter: Category?

    init(route: MonthRoute) {
        monthKey = route.monthKey
        _categoryFilter = State(initialValue: route.category)
    }

    private var settings: BudgetSettings? { settingsList.first }
    private var currentMonth: String { MonthKey.key(for: .now) }
    private var isFuture: Bool { monthKey > currentMonth }
    private var isPast: Bool { monthKey < currentMonth }
    private var living: Int { settings?.livingMonthlyCents ?? 0 }
    private var dueBills: [Bill] { bills.filter { $0.isDue(in: monthKey) } }
    private var billsPlanned: Int { dueBills.reduce(0) { $0 + $1.amountCents } }

    private var monthExpenses: [Expense] {
        // Compare against the month's dates (cheap) rather than formatting a key for every expense.
        guard let first = MonthKey.firstDay(of: monthKey),
              let month = Calendar.current.dateInterval(of: .month, for: first) else { return [] }
        return allExpenses.filter { $0.date >= month.start && $0.date < month.end }
    }

    /// Each day of this month up to today (from the first day you used the app), newest first.
    private var daySummaries: [BudgetCalculator.DaySummary] {
        guard let first = MonthKey.firstDay(of: monthKey),
              let last = Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: first) else { return [] }
        let end = min(last, Date.now)
        guard end >= first else { return [] }
        let start = Calendar.current.startOfDay(for: settings?.streakStartDate ?? first)
        return calculator.daySummaries(inMonthOf: end).filter { $0.day >= start }
    }

    private var calculator: BudgetCalculator {
        BudgetCalculator(expenses: allExpenses, settings: settings, incomes: incomes)
    }

    private var spending: BudgetCalculator.MonthSpending {
        BudgetCalculator(expenses: allExpenses, settings: settings, incomes: incomes)
            .monthlySpending(months: [monthKey]).first ?? BudgetCalculator.MonthSpending(monthKey: monthKey)
    }

    private var planned: Int {
        BudgetCalculator.plannedCents(month: monthKey, livingMonthlyCents: living,
                                      bills: bills.map { (cents: $0.amountCents, dueMonths: $0.dueMonths) }
                                          + subscriptions.map { $0.asPlanned(in: [monthKey]) })
    }

    private var caption: String {
        let year = MonthKey.components(of: monthKey).map { String($0.year) } ?? ""
        if isFuture { return "\(year) · Coming up" }
        if isPast { return "\(year) · Finished" }
        return "\(year) · This month"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ScreenHeader(caption: caption, verbatimTitle: MonthKey.title(of: monthKey))
                summaryCard
                billsCard
                if !categoryTotals.isEmpty { categoriesCard }
                expensesSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(GlowBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $editing) { e in
            AddExpenseView(editing: e)
                .presentationBackground(Theme.base)
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        let total = spending.totalCents
        let over = total > planned
        let fraction = planned > 0 ? min(1, Double(total) / Double(planned)) : 0
        let livingLeft = living - spending.livingCents
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isFuture ? "Planned" : "Spent").font(.subheadline.weight(.semibold))
                    Text(isFuture ? "Nothing spent yet" : "of \(Money.format(planned)) planned")
                        .font(.caption)
                        .foregroundStyle(over ? Theme.warn : Theme.secondary)
                }
                Spacer()
                Text(isFuture ? Money.format(planned) : Money.format(total, alwaysShowCents: true))
                    .font(Theme.rounded(30))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.ink.opacity(0.12))
                    Rectangle()
                        .fill(over ? AnyShapeStyle(Theme.warn) : AnyShapeStyle(Theme.mint))
                        .frame(width: max(0, geo.size.width * fraction))
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 10) {
                groupStat("Everyday", spending.livingCents, of: living, Theme.mint)
                groupStat("Bills", spending.billsCents, of: billsPlanned, Category.bills.color)
                groupStat("Engagement", spending.engagementCents, of: nil, Category.engagement.color)
            }

            if !isFuture {
                Divider().overlay(Theme.ink.opacity(0.14))
                HStack {
                    Text(livingLeft < 0 ? "Everyday money over by"
                         : isPast ? "Saved to emergency" : "Everyday money left")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                    Spacer()
                    Text(Money.format(abs(livingLeft), alwaysShowCents: true))
                        .font(Theme.rounded(16))
                        .foregroundStyle(livingLeft < 0 ? Theme.warn : Theme.mint)
                }
            }
        }
        .padding(16)
        .glassCard(radius: 28)
    }

    private func groupStat(_ name: LocalizedStringKey, _ cents: Int, of plan: Int?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(name).font(.caption2).foregroundStyle(Theme.secondary)
            }
            Text(Money.format(cents, alwaysShowCents: true)).font(Theme.rounded(15))
            if let plan {
                Text("of \(Money.format(plan))").font(.caption2).foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Bills

    private var billsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bills").font(.title3.weight(.bold)).padding(.horizontal, 4)
            VStack(spacing: 0) {
                if dueBills.isEmpty {
                    Text("No bills due in \(MonthKey.title(of: monthKey)).")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
                }
                ForEach(dueBills) { bill in
                    let paid = bill.isPaid(in: monthKey)
                    Button {
                        withAnimation(.snappy) { BillPayments.toggle(bill: bill, month: monthKey, in: context) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: paid ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(paid ? Theme.mint : Theme.ink.opacity(0.5))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(bill.name).font(.subheadline.weight(.semibold))
                                    .strikethrough(paid, color: Theme.ink.opacity(0.6))
                                if let day = bill.dueDay, !paid,
                                   let due = BillSchedule.dueDate(month: monthKey, day: day) {
                                    Text("Paid automatically on \(due.formatted(.dateTime.month(.abbreviated).day().locale(AppLanguage.locale)))")
                                        .font(.caption).foregroundStyle(Theme.sky)
                                } else {
                                    Text(paid ? "Paid · counted as spent" : "Tap to mark paid")
                                        .font(.caption).foregroundStyle(Theme.secondary)
                                }
                            }
                            Spacer()
                            Text(Money.format(bill.amountCents)).font(Theme.rounded(16))
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("\(bill.name), \(Money.format(bill.amountCents)), \(paid ? "paid" : "not paid")")
                    .accessibilityHint(paid ? "Marks it unpaid" : "Marks it paid")
                    if bill.id != dueBills.last?.id { Divider().overlay(Theme.ink.opacity(0.14)) }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 2)
            .glassCard()
        }
    }

    // MARK: - Categories

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

    private var categoriesCard: some View {
        let maxValue = max(1, categoryTotals.first?.cents ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("By category · tap to filter").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
            ForEach(categoryTotals) { item in
                let selected = categoryFilter == item.category
                Button {
                    withAnimation(.snappy) { categoryFilter = selected ? nil : item.category }
                } label: {
                    HStack(spacing: 10) {
                        CategoryIcon(category: item.category, size: 28)
                        Text(item.category.title).font(.footnote.weight(.semibold))
                            .frame(width: 78, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Theme.ink.opacity(0.12))
                                Rectangle().fill(item.category.color)
                                    .frame(width: max(6, geo.size.width * CGFloat(item.cents) / CGFloat(maxValue)))
                            }
                        }
                        .frame(height: 8)
                        Text(Money.format(item.cents, alwaysShowCents: true)).font(Theme.rounded(13))
                            .frame(width: 64, alignment: .trailing)
                    }
                    .padding(.vertical, 4).padding(.horizontal, 6)
                    .background(selected ? Theme.ink.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(14)
        .glassCard(radius: 24)
    }

    // MARK: - Expenses

    private var filteredExpenses: [Expense] {
        guard let categoryFilter else { return monthExpenses }
        return monthExpenses.filter { $0.category == categoryFilter }
    }

    private var days: [(day: Date, items: [Expense])] {
        let groups = Dictionary(grouping: filteredExpenses) { Calendar.current.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    private var expensesSection: some View {
        // Worked out once here, not again for every row.
        let daySummaries = self.daySummaries
        let days = self.days
        let byDay = Dictionary(grouping: monthExpenses) { Calendar.current.startOfDay(for: $0.date) }
        let incomeByDay = Dictionary(grouping: incomes) { Calendar.current.startOfDay(for: $0.date) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Expenses").font(.title3.weight(.bold))
                Spacer()
                if let categoryFilter {
                    Button {
                        withAnimation(.snappy) { self.categoryFilter = nil }
                    } label: {
                        HStack(spacing: 4) {
                            Text(categoryFilter.title)
                            Image(systemName: "xmark")
                        }
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10).frame(height: 28)
                        .glassCard(radius: 14)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Show all categories")
                }
            }
            .padding(.horizontal, 4)

            if days.isEmpty && (categoryFilter != nil || daySummaries.isEmpty) {
                Text(emptyText)
                    .font(.subheadline).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .glassCard()
            }
            if categoryFilter == nil, !daySummaries.isEmpty {
                // Same as History's "day by day": every day, spent of its limit; tap to see the expenses.
                VStack(spacing: 0) {
                    ForEach(daySummaries) { day in
                        DaySummaryRow(day: day,
                                      items: byDay[day.day] ?? [],
                                      incomes: incomeByDay[day.day] ?? [],
                                      isOpen: openDay == day.day) {
                            withAnimation(.snappy) { openDay = openDay == day.day ? nil : day.day }
                        }
                        if day.id != daySummaries.last?.id { Divider().overlay(Theme.ink.opacity(0.12)) }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .glassCard(radius: 22)
            } else if !days.isEmpty {
                VStack(spacing: 0) {
                    ForEach(days, id: \.day) { group in
                        dayRow(group)
                        if group.day != days.last?.day { Divider().overlay(Theme.ink.opacity(0.12)) }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .glassCard(radius: 22)
            }
            if !days.isEmpty {
                Text(categoryFilter == nil ? "Tap a day to see what you spent." : "Tap a day to see its expenses. Tap to edit, swipe left to delete, right to add again.")
                    .font(.caption).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// One line per day; tap to show that day's expenses underneath.
    private func dayRow(_ group: (day: Date, items: [Expense])) -> some View {
        let isOpen = openDay == group.day
        let summary = categoryFilter == nil ? calculator.summary(on: group.day) : nil
        let total = group.items.reduce(0) { $0 + $1.amountCents }
        return VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { openDay = isOpen ? nil : group.day }
            } label: {
                HStack(spacing: 10) {
                    if let summary {
                        Circle().fill(summary.isOver ? Theme.warn : Theme.mint).frame(width: 8, height: 8)
                    }
                    Text(group.day.formatted(.dateTime.weekday(.abbreviated).day().locale(AppLanguage.locale)))
                        .font(.subheadline.weight(.semibold))
                    Text("^[\(group.items.count) item](inflect: true)").font(.caption).foregroundStyle(Theme.secondary)
                    Spacer()
                    Text(Money.format(total, alwaysShowCents: true)).font(Theme.rounded(16))
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold)).foregroundStyle(Theme.secondary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityHint(Text(isOpen ? "Hides this day's expenses" : "Shows this day's expenses"))

            if isOpen {
                VStack(spacing: 0) {
                    ForEach(group.items.sorted { $0.date < $1.date }) { e in
                        Button { editing = e } label: { ExpenseRow(expense: e) }
                            .buttonStyle(.pressable)
                            .expenseSwipe(e)
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editing = e }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    DeleteUndo.shared.delete(e, in: context)
                                }
                            }
                    }
                    if let summary, !summary.isOver, summary.spentCents > 0 {
                        Text("\(Money.format(summary.leftCents, alwaysShowCents: true)) under the limit")
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.mint)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 10)
                    } else if let summary, summary.isOver {
                        Text("\(Money.format(summary.spentCents - summary.limitCents, alwaysShowCents: true)) over the limit")
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.warn)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 10)
                    }
                }
                .padding(.leading, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var emptyText: String {
        if let categoryFilter { return String(localized: "No \(categoryFilter.title.lowercased()) expenses in \(MonthKey.title(of: monthKey)).", bundle: AppLanguage.bundle) }
        if isFuture { return "\(MonthKey.title(of: monthKey)) hasn't started yet. The bills above are what's planned." }
        return String(localized: "No expenses in \(MonthKey.title(of: monthKey)) yet. Tap + to add one.", bundle: AppLanguage.bundle)
    }
}
