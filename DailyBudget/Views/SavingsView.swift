import SwiftUI
import SwiftData

struct SavingsRoute: Hashable {}

/// Emergency savings month by month, the Engagement money as a goal, and all extra income.
struct SavingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]
    @Query private var settingsList: [BudgetSettings]
    @State private var editingIncome: Income?
    @State private var adding = false

    private var settings: BudgetSettings? { settingsList.first }
    private var calc: BudgetCalculator { BudgetCalculator(expenses: expenses, settings: settings, incomes: incomes) }
    private var months: [BudgetCalculator.SavingsMonth] {
        calc.savingsByMonth(planMonths: settings?.planMonths ?? [], today: .now,
                            savingsIncomeByMonth: Income.byMonth(incomes, target: .savings))
    }
    private var total: Int { settings?.savingsCents(calc, incomes: incomes) ?? 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ScreenHeader(caption: "Money kept aside", title: "Savings")
                totalCard
                engagementCard
                incomeSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(GlowBackground())
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $editingIncome) { i in
            AddExpenseView(editingIncome: i).presentationBackground(Theme.base)
        }
        .sheet(isPresented: $adding) {
            AddExpenseView().presentationBackground(Theme.base)
        }
    }

    // MARK: Emergency savings

    private var totalCard: some View {
        let maxValue = max(1, months.map(\.totalCents).max() ?? 1)
        let before = settings?.savedBeforeCents ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Emergency savings").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                    Text(Money.format(total, alwaysShowCents: true)).font(Theme.rounded(38))
                }
                Spacer()
                Image(systemName: "banknote.fill").font(.system(size: 26)).foregroundStyle(Theme.sky)
            }
            Text("Living money you didn't spend goes here when a month ends, plus extra money you saved.")
                .font(.caption).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if months.isEmpty {
                Text("Nothing yet. Your first month adds to it when it ends.")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(months) { m in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(MonthKey.title(of: m.monthKey)).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(m.totalCents > 0 ? "+\(Money.format(m.totalCents, alwaysShowCents: true))" : "–")
                                    .font(Theme.rounded(15))
                                    .foregroundStyle(m.totalCents > 0 ? Theme.mint : Theme.secondary)
                            }
                            GeometryReader { geo in
                                HStack(spacing: 2) {
                                    if m.leftoverCents > 0 {
                                        Rectangle().fill(Theme.mint)
                                            .frame(width: geo.size.width * CGFloat(m.leftoverCents) / CGFloat(maxValue))
                                    }
                                    if m.incomeCents > 0 {
                                        Rectangle().fill(Theme.sky)
                                            .frame(width: geo.size.width * CGFloat(m.incomeCents) / CGFloat(maxValue))
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                            .frame(height: 8)
                            .background(Theme.ink.opacity(0.08), in: Rectangle())
                            Text(note(for: m)).font(.caption).foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
            if before > 0 {
                HStack {
                    Text("From earlier plans").font(.footnote).foregroundStyle(Theme.secondary)
                    Spacer()
                    Text(Money.format(before, alwaysShowCents: true)).font(Theme.rounded(15))
                }
            }
        }
        .padding(18)
        .glassCard(radius: 28)
    }

    private func note(for m: BudgetCalculator.SavingsMonth) -> String {
        let current = MonthKey.key(for: .now)
        var parts: [String] = []
        if m.leftoverCents > 0 {
            parts.append(String(localized: "\(Money.format(m.leftoverCents, alwaysShowCents: true)) left over", bundle: AppLanguage.bundle))
        } else if m.monthKey >= current {
            parts.append(String(localized: "Adds what's left when the month ends", bundle: AppLanguage.bundle))
        } else {
            parts.append(String(localized: "Nothing left over", bundle: AppLanguage.bundle))
        }
        if m.incomeCents > 0 {
            parts.append(String(localized: "\(Money.format(m.incomeCents, alwaysShowCents: true)) extra saved", bundle: AppLanguage.bundle))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Engagement goal

    private var engagementCard: some View {
        let setAside = settings?.engagementCents ?? 0
        let extra = Income.total(incomes, target: .engagement)
        let budget = setAside + extra
        let spent = expenses.filter { $0.category == .engagement }.reduce(0) { $0 + $1.amountCents }
        let left = budget - spent
        let fraction = budget > 0 ? min(1, Double(spent) / Double(budget)) : 0
        return NavigationLink(value: MonthRoute(monthKey: MonthKey.key(for: .now), category: .engagement)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    CategoryIcon(category: .engagement, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Engagement").font(.subheadline.weight(.semibold))
                        Text(extra > 0 ? "\(Money.format(setAside)) set aside + \(Money.format(extra, alwaysShowCents: true)) extra"
                                       : "\(Money.format(setAside)) set aside")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
                }
                GeometryReader { geo in
                    Rectangle().fill(Category.engagement.color)
                        .frame(width: max(0, geo.size.width * fraction))
                }
                .frame(height: 10)
                .background(Theme.ink.opacity(0.1), in: Rectangle())
                HStack {
                    stat("Used", spent)
                    Spacer()
                    stat(left >= 0 ? "Left" : "Over", abs(left), color: left >= 0 ? Theme.mint : Theme.warn)
                }
            }
            .padding(18)
            .glassCard(radius: 28)
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Shows engagement spending")
    }

    private func stat(_ title: LocalizedStringKey, _ cents: Int, color: Color = Theme.ink) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
            Text(Money.format(cents, alwaysShowCents: true)).font(Theme.rounded(18)).foregroundStyle(color)
        }
    }

    // MARK: Extra income

    private var incomeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Extra money").font(.headline)
                Spacer()
                Button("Add") { adding = true }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.mint)
            }
            .padding(.horizontal, 4)
            if incomes.isEmpty {
                Text("Got a gift or side-job money? Tap + and choose \"I got money\".")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16).glassCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(incomes) { i in
                        Button { editingIncome = i } label: { IncomeRow(income: i, showDate: true) }
                            .buttonStyle(.pressable)
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editingIncome = i }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    context.delete(i)
                                    try? context.save()
                                }
                            }
                        if i.id != incomes.last?.id { Divider().overlay(Theme.rule) }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .glassCard()
                Text("Tap to edit. Press and hold to delete.").font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }
}

/// A row for extra income in lists: green, with a plus. `size` below 36 gives the compact form used inside day rows.
struct IncomeRow: View {
    let income: Income
    var size: CGFloat = 40
    /// The Savings list shows the date; lists that are already one day show only where it went.
    var showDate = false

    private var compact: Bool { size < 36 }

    var body: some View {
        HStack(spacing: compact ? 10 : 12) {
            IncomeIcon(target: income.target, size: size)
            VStack(alignment: .leading, spacing: 1) {
                Text(income.note.isEmpty ? String(localized: "Extra money", bundle: AppLanguage.bundle) : income.note)
                    .font(compact ? .footnote.weight(.semibold) : .subheadline.weight(.semibold)).lineLimit(1)
                if !compact {
                    Group {
                        if showDate {
                            Text("\(income.target.title) · \(income.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: AppLanguage.locale)))")
                        } else {
                            Text(income.target.title)
                        }
                    }
                    .font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text("+\(Money.format(income.amountCents, alwaysShowCents: true))")
                .font(Theme.rounded(compact ? 14 : 16)).foregroundStyle(Theme.mint)
        }
        .padding(.vertical, compact ? 0 : 10)
        .contentShape(Rectangle())
    }
}
