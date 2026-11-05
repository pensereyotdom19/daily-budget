import SwiftUI
import SwiftData

/// Navigation value for the "Spent so far" screen.
struct SpendingRoute: Hashable {}

/// Everything spent since the plan started: total vs plan, where it went,
/// categories (tap to filter), biggest expenses, and all expenses by month.
struct SpendingOverviewView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var subscriptions: [Subscription]
    @Query private var settingsList: [BudgetSettings]
    @Query(sort: \Bill.sortOrder) private var bills: [Bill]
    @State private var editing: Expense?
    @State private var categoryFilter: Category?

    private var settings: BudgetSettings? { settingsList.first }
    private var currentMonth: String { MonthKey.key(for: .now) }
    private var monthsSoFar: [String] { (settings?.planMonths ?? [currentMonth]).filter { $0 <= currentMonth } }
    private var calc: BudgetCalculator { BudgetCalculator(expenses: allExpenses, settings: settings, incomes: incomes) }

    /// Expenses inside the plan months so far.
    private var expenses: [Expense] {
        let months = Set(monthsSoFar)
        return allExpenses.filter { months.contains(MonthKey.key(for: $0.date)) }
    }

    private var spending: [BudgetCalculator.MonthSpending] { calc.monthlySpending(months: monthsSoFar) }
    private var total: Int { spending.reduce(0) { $0 + $1.totalCents } }
    private var livingSpent: Int { spending.reduce(0) { $0 + $1.livingCents } }
    private var billsSpent: Int { spending.reduce(0) { $0 + $1.billsCents } }
    private var engagementSpent: Int { spending.reduce(0) { $0 + $1.engagementCents } }

    private var plannedSoFar: Int {
        monthsSoFar.reduce(0) { sum, month in
            sum + BudgetCalculator.plannedCents(month: month, livingMonthlyCents: settings?.livingMonthlyCents ?? 0,
                                                bills: bills.map { (cents: $0.amountCents, dueMonths: $0.dueMonths) }
                                                    + subscriptions.map { $0.asPlanned(in: [month]) })
        }
    }

    /// Days counted for the everyday average: from first use (or plan start) through today.
    private var daysSoFar: Int {
        let start = Calendar.current.startOfDay(for: settings?.streakStartDate ?? .now)
        let days = Calendar.current.dateComponents([.day], from: start, to: Calendar.current.startOfDay(for: .now)).day ?? 0
        return max(1, days + 1)
    }

    private var rangeCaption: String {
        let start = settings?.planStartDate ?? .now
        let from = start.formatted(.dateTime.month(.abbreviated).day().locale(AppLanguage.locale))
        return String(localized: "\(from) – today", bundle: AppLanguage.bundle)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ScreenHeader(caption: rangeCaption, title: "Spent so far")
                totalCard
                whereItWentCard
                if !categoryTotals.isEmpty { categoriesCard }
                if !biggest.isEmpty { biggestCard }
                allExpensesSection
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

    // MARK: - Total

    private var totalCard: some View {
        let diff = plannedSoFar - total
        let fraction = plannedSoFar > 0 ? min(1, Double(total) / Double(plannedSoFar)) : 0
        let saved = settings?.savingsCents(calc, incomes: incomes) ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(Money.format(total, alwaysShowCents: true)).font(Theme.rounded(38))
                Spacer()
                Text("of \(Money.format(plannedSoFar)) planned")
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(diff < 0 ? AnyShapeStyle(Theme.warn) : AnyShapeStyle(Theme.accentGradient))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)
            HStack(spacing: 10) {
                stat(diff >= 0 ? "Under plan" : "Over plan", Money.format(abs(diff), alwaysShowCents: true),
                     diff >= 0 ? Theme.mint : Theme.warn)
                stat("Everyday / day", Money.format(livingSpent / daysSoFar, alwaysShowCents: true), .white)
                stat("Saved", Money.format(saved, alwaysShowCents: true), Theme.sky)
            }
        }
        .padding(18)
        .glassCard(radius: 28)
    }

    private func stat(_ title: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondary).lineLimit(1)
            Text(value).font(Theme.rounded(16)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Where it went

    private var whereItWentCard: some View {
        let groups: [(String, Int, Color, String)] = [
            ("Everyday", livingSpent, Theme.mint, "Food, coffee, transport…"),
            ("Bills", billsSpent, Category.bills.color, "Paid bills"),
            ("Engagement", engagementSpent, Category.engagement.color, "From the money set aside"),
        ]
        return VStack(alignment: .leading, spacing: 12) {
            Text("Where it went").font(.title3.weight(.bold))
            // One bar split by group.
            GeometryReader { geo in
                let scale = geo.size.width / CGFloat(max(1, total))
                HStack(spacing: 0) {
                    ForEach(groups, id: \.0) { g in
                        Rectangle().fill(g.2).frame(width: CGFloat(g.1) * scale)
                    }
                    Spacer(minLength: 0)
                }
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
            }
            .frame(height: 12)
            .accessibilityHidden(true)
            ForEach(groups, id: \.0) { g in
                HStack(spacing: 10) {
                    Circle().fill(g.2).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(g.0).font(.subheadline.weight(.semibold))
                        Text(g.3).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Money.format(g.1, alwaysShowCents: true)).font(Theme.rounded(16))
                        Text(percent(g.1)).font(.caption2).foregroundStyle(Theme.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .glassCard(radius: 24)
    }

    private func percent(_ cents: Int) -> String {
        guard total > 0, cents > 0 else { return "0%" }
        let value = Int((Double(cents) / Double(total) * 100).rounded())
        return value == 0 ? "<1%" : "\(value)%"
    }

    // MARK: - Categories

    private struct CategoryTotal: Identifiable {
        let category: Category
        let cents: Int
        let count: Int
        var id: String { category.rawValue }
    }

    private var categoryTotals: [CategoryTotal] {
        var totals: [Category: (Int, Int)] = [:]
        for e in expenses {
            let t = totals[e.category] ?? (0, 0)
            totals[e.category] = (t.0 + e.amountCents, t.1 + 1)
        }
        return totals.map { CategoryTotal(category: $0.key, cents: $0.value.0, count: $0.value.1) }
            .sorted { $0.cents > $1.cents }
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
                        CategoryIcon(category: item.category, size: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.category.title).font(.footnote.weight(.semibold))
                                Text("\(item.count)×").font(.caption2).foregroundStyle(Theme.secondary)
                                Spacer()
                                Text(Money.format(item.cents, alwaysShowCents: true)).font(Theme.rounded(14))
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.12))
                                    Capsule().fill(item.category.color)
                                        .frame(width: max(6, geo.size.width * CGFloat(item.cents) / CGFloat(maxValue)))
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                    .padding(.vertical, 5).padding(.horizontal, 6)
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

    // MARK: - Biggest

    /// The five largest everyday expenses (bill payments are left out; they're expected).
    private var biggest: [Expense] {
        Array(expenses.filter { $0.billID == nil }.sorted { $0.amountCents > $1.amountCents }.prefix(5))
    }

    private var biggestCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Biggest expenses").font(.title3.weight(.bold)).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(biggest) { e in
                    expenseButton(e, showDate: true)
                    if e.id != biggest.last?.id { Divider().overlay(Color.white.opacity(0.14)) }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 2)
            .glassCard(radius: 22)
        }
    }

    // MARK: - All expenses

    private var filtered: [Expense] {
        guard let categoryFilter else { return expenses }
        return expenses.filter { $0.category == categoryFilter }
    }

    private var allExpensesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("All expenses").font(.title3.weight(.bold))
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

            if filtered.isEmpty {
                Text(categoryFilter == nil ? "Nothing spent yet. Tap + to add an expense."
                                           : "No \(categoryFilter!.title.lowercased()) expenses yet.")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity).padding(20)
                    .glassCard()
            }
            ForEach(monthsSoFar.reversed(), id: \.self) { month in
                let items = filtered.filter { MonthKey.key(for: $0.date) == month }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        NavigationLink(value: MonthRoute(monthKey: month, category: categoryFilter)) {
                            HStack {
                                Text(MonthKey.title(of: month))
                                Text("· \(items.count)").foregroundStyle(Theme.secondary)
                                Spacer()
                                Text(Money.format(items.reduce(0) { $0 + $1.amountCents }, alwaysShowCents: true))
                                Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                                    .foregroundStyle(Theme.secondary)
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityHint("Opens \(MonthKey.title(of: month))")
                        VStack(spacing: 0) {
                            ForEach(items) { e in
                                expenseButton(e, showDate: true)
                                if e.id != items.last?.id { Divider().overlay(Color.white.opacity(0.14)) }
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 2)
                        .glassCard(radius: 22)
                    }
                }
            }
            if !filtered.isEmpty {
                Text("Tap an expense to edit it. Press and hold to delete.")
                    .font(.caption).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func expenseButton(_ e: Expense, showDate: Bool) -> some View {
        Button { editing = e } label: {
            HStack(spacing: 12) {
                CategoryIcon(category: e.category, size: 36, symbol: e.iconSymbol)
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.note.isEmpty ? e.category.title : e.note).font(.subheadline.weight(.semibold))
                    Text("\(e.category.title) · \(e.date.formatted(.dateTime.month(.abbreviated).day().locale(AppLanguage.locale)))")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text(Money.format(e.amountCents, alwaysShowCents: true)).font(Theme.rounded(16))
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editing = e }
            Button("Delete", systemImage: "trash", role: .destructive) {
                BillPayments.delete(e, in: context)
            }
        }
    }
}
