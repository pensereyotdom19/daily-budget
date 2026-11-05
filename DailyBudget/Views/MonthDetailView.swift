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
        allExpenses.filter { MonthKey.key(for: $0.date) == monthKey }
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
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(over ? AnyShapeStyle(Theme.warn) : AnyShapeStyle(Theme.accentGradient))
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
                Divider().overlay(Color.white.opacity(0.14))
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
                                .foregroundStyle(paid ? Theme.mint : .white.opacity(0.5))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(bill.name).font(.subheadline.weight(.semibold))
                                    .strikethrough(paid, color: .white.opacity(0.6))
                                Text(paid ? "Paid · counted as spent" : "Tap to mark paid")
                                    .font(.caption).foregroundStyle(Theme.secondary)
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
                    if bill.id != dueBills.last?.id { Divider().overlay(Color.white.opacity(0.14)) }
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
                                Capsule().fill(Color.white.opacity(0.12))
                                Capsule().fill(item.category.color)
                                    .frame(width: max(6, geo.size.width * CGFloat(item.cents) / CGFloat(maxValue)))
                            }
                        }
                        .frame(height: 8)
                        Text(Money.format(item.cents, alwaysShowCents: true)).font(Theme.rounded(13))
                            .frame(width: 64, alignment: .trailing)
                    }
                    .padding(.vertical, 4).padding(.horizontal, 6)
                    .background(selected ? Color.white.opacity(0.12) : Color.clear,
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
        VStack(alignment: .leading, spacing: 8) {
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

            if days.isEmpty {
                Text(emptyText)
                    .font(.subheadline).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .glassCard()
            }
            ForEach(days, id: \.day) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(group.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(AppLanguage.locale)))
                        Spacer()
                        Text(Money.format(group.items.reduce(0) { $0 + $1.amountCents }, alwaysShowCents: true))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 6)
                    VStack(spacing: 0) {
                        ForEach(group.items) { e in
                            Button { editing = e } label: { ExpenseRow(expense: e) }
                                .buttonStyle(.pressable)
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") { editing = e }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        BillPayments.delete(e, in: context)
                                    }
                                }
                            if e.id != group.items.last?.id { Divider().overlay(Color.white.opacity(0.14)) }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 2)
                    .glassCard(radius: 22)
                }
            }
            if !days.isEmpty {
                Text("Tap an expense to edit it. Press and hold to delete.")
                    .font(.caption).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var emptyText: String {
        if let categoryFilter { return String(localized: "No \(categoryFilter.title.lowercased()) expenses in \(MonthKey.title(of: monthKey)).", bundle: AppLanguage.bundle) }
        if isFuture { return "\(MonthKey.title(of: monthKey)) hasn't started yet. The bills above are what's planned." }
        return String(localized: "No expenses in \(MonthKey.title(of: monthKey)) yet. Tap + to add one.", bundle: AppLanguage.bundle)
    }
}
