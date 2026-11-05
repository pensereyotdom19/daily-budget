import SwiftUI
import SwiftData

/// History: the whole plan at a glance, one row per month (tap to open it),
/// then this month day by day.
struct HistoryView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var subscriptions: [Subscription]
    @Query private var settingsList: [BudgetSettings]
    @Query(sort: \Bill.sortOrder) private var bills: [Bill]
    /// Normally empty. For screenshots during development, launch with `-openSpending YES`.
    @State private var path: NavigationPath = {
        var p = NavigationPath()
        if UserDefaults.standard.bool(forKey: "openSpending") { p.append(SpendingRoute()) }
        return p
    }()

    private var settings: BudgetSettings? { settingsList.first }
    private var calc: BudgetCalculator { BudgetCalculator(expenses: expenses, settings: settings, incomes: incomes) }
    private var currentMonth: String { MonthKey.key(for: .now) }
    private var planMonths: [String] { settings?.planMonths ?? [currentMonth] }
    /// Includes months of earlier plans, so History keeps them after a new plan starts.
    private var historyMonths: [String] { settings?.historyMonths ?? [currentMonth] }
    private var living: Int { settings?.livingMonthlyCents ?? 0 }

    private func planned(_ month: String) -> Int {
        BudgetCalculator.plannedCents(month: month, livingMonthlyCents: living,
                                      bills: bills.map { (cents: $0.amountCents, dueMonths: $0.dueMonths) }
                                          + subscriptions.map { $0.asPlanned(in: [month]) })
    }

    /// The day opened in "day by day" (only one at a time).
    @State private var openDay: Date?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
                    HStack(alignment: .bottom) {
                        ScreenHeader(caption: rangeCaption, title: "History")
                        NavigationLink(value: SearchRoute()) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 44, height: 44)
                                .glassCard(radius: 22)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("Search expenses")
                    }
                    NavigationLink(value: SpendingRoute()) { overviewCard }
                        .buttonStyle(.pressable)
                        .accessibilityHint("Shows where your money went")
                    TrendCard(months: calc.monthlySpending(months: historyMonths),
                              budget: { key in MonthKey.firstDay(of: key).map { calc.livingBudget(inMonthOf: $0) } ?? living },
                              currentMonth: currentMonth)
                    monthsSection
                    daysSection
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
            .navigationDestination(for: MonthRoute.self) { route in
                MonthDetailView(route: route)
            }
            .navigationDestination(for: SpendingRoute.self) { _ in
                SpendingOverviewView()
            }
            .navigationDestination(for: SearchRoute.self) { _ in SearchView() }
        }
    }

    private var rangeCaption: String {
        guard let first = planMonths.first, let last = planMonths.last,
              let a = MonthKey.firstDay(of: first), let b = MonthKey.firstDay(of: last) else { return "" }
        return "\(a.formatted(.dateTime.month(.abbreviated).year().locale(AppLanguage.locale))) – \(b.formatted(.dateTime.month(.abbreviated).year().locale(AppLanguage.locale)))"
    }

    // MARK: - Overview

    private var overviewCard: some View {
        let soFar = planMonths.filter { $0 <= currentMonth }
        let spent = calc.monthlySpending(months: soFar).reduce(0) { $0 + $1.totalCents }
        let plannedSoFar = soFar.reduce(0) { $0 + planned($1) }
        let diff = plannedSoFar - spent
        let saved = settings?.savingsCents(calc, incomes: incomes) ?? 0
        let finished = soFar.filter { $0 < currentMonth }
        let finishedSpent = calc.monthlySpending(months: finished).reduce(0) { $0 + $1.totalCents }
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("SPENT SO FAR").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Details")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
                }
                Text(Money.format(spent, alwaysShowCents: true)).font(Theme.rounded(38))
                if finished.count >= 2 {
                    Text("About \(Money.format(finishedSpent / finished.count)) per finished month")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            HStack(spacing: 10) {
                overviewStat("Planned", Money.format(plannedSoFar), Theme.secondary)
                overviewStat(diff >= 0 ? "Under plan" : "Over plan",
                             Money.format(abs(diff), alwaysShowCents: true), diff >= 0 ? Theme.mint : Theme.warn)
                overviewStat("Saved", Money.format(saved, alwaysShowCents: true), Theme.sky)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 28)
    }

    private func overviewStat(_ title: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondary)
            Text(value).font(Theme.rounded(16)).foregroundStyle(color == Theme.secondary ? .white : color)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Month by month

    private var monthsSection: some View {
        let data = calc.monthlySpending(months: historyMonths)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Month by month").font(.title3.weight(.bold))
                Spacer()
                HStack(spacing: 10) {
                    legendDot("Everyday", Theme.mint)
                    legendDot("Bills", Category.bills.color)
                    legendDot("Engagement", Category.engagement.color)
                }
            }
            .padding(.horizontal, 4)
            ForEach(data) { m in
                NavigationLink(value: MonthRoute(monthKey: m.monthKey)) {
                    MonthRow(spending: m,
                             plannedCents: planned(m.monthKey),
                             stage: m.monthKey < currentMonth ? .finished : m.monthKey == currentMonth ? .now : .upcoming,
                             specialBills: specialBills(in: m.monthKey))
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Opens \(MonthKey.title(of: m.monthKey))")
            }
        }
    }

    private func legendDot(_ name: LocalizedStringKey, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name).font(.caption2).foregroundStyle(Theme.secondary)
        }
    }

    /// Bills that aren't due every month, e.g. "Credit card $700 · Water $5".
    private func specialBills(in month: String) -> String? {
        let list = bills.filter { $0.isDue(in: month) && $0.dueMonths.count < planMonths.count }
        guard !list.isEmpty else { return nil }
        return list.map { "\($0.name) \(Money.format($0.amountCents))" }.joined(separator: " · ")
    }

    // MARK: - This month, day by day

    /// Days of this month from the first day the app was used, newest first.
    private var days: [BudgetCalculator.DaySummary] {
        let start = Calendar.current.startOfDay(for: settings?.streakStartDate ?? .now)
        return calc.daySummaries(inMonthOf: .now).filter { $0.day >= start }
    }

    private var daysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(MonthKey.title(of: currentMonth)), day by day").font(.title3.weight(.bold))
                Spacer()
                Text("everyday money").font(.caption2).foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
            VStack(spacing: 0) {
                ForEach(days) { day in
                    DaySummaryRow(day: day,
                                  items: expenses.filter { Calendar.current.isDate($0.date, inSameDayAs: day.day) },
                                  isOpen: openDay == day.day) {
                        withAnimation(.snappy) { openDay = openDay == day.day ? nil : day.day }
                    }
                    if day.id != days.last?.id { Divider().overlay(Color.white.opacity(0.12)) }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
            .glassCard(radius: 22)
            Text("Tap a day to see what you spent.")
                .font(.caption).foregroundStyle(Theme.secondary).padding(.horizontal, 4)
        }
    }

}

/// One month in "Month by month": spent vs planned with a bar split into everyday, bills and engagement.
private struct MonthRow: View {
    enum Stage { case finished, now, upcoming }

    let spending: BudgetCalculator.MonthSpending
    let plannedCents: Int
    let stage: Stage
    let specialBills: String?

    private var total: Int { spending.totalCents }
    private var diff: Int { plannedCents - total }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(MonthKey.title(of: spending.monthKey)).font(.headline)
                stageChip
                Spacer()
                if stage == .upcoming {
                    Text(Money.format(plannedCents)).font(Theme.rounded(17)).foregroundStyle(Theme.secondary)
                } else {
                    Text(Money.format(total, alwaysShowCents: true)).font(Theme.rounded(17))
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold)).foregroundStyle(Theme.secondary)
            }
            if stage != .upcoming { bar }
            HStack(alignment: .firstTextBaseline) {
                Text(leftText).lineLimit(1)
                    .foregroundStyle(stage == .upcoming && specialBills != nil ? Theme.warn : Theme.secondary)
                Spacer()
                Text(rightText).fontWeight(.semibold).foregroundStyle(rightColor)
            }
            .font(.caption)
        }
        .padding(14)
        .glassCard(radius: 22)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var stageChip: some View {
        switch stage {
        case .now:
            chip("NOW", Theme.mint.opacity(0.25))
        case .finished:
            chip("DONE", Color.white.opacity(0.12))
        case .upcoming:
            EmptyView()
        }
    }

    private func chip(_ text: LocalizedStringKey, _ background: Color) -> some View {
        Text(text).font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(background, in: Capsule())
    }

    private var bar: some View {
        GeometryReader { geo in
            let scale = geo.size.width / CGFloat(max(1, max(plannedCents, total)))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(stage == .upcoming ? 0.07 : 0.12))
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.mint).frame(width: CGFloat(spending.livingCents) * scale)
                    Rectangle().fill(Category.bills.color).frame(width: CGFloat(spending.billsCents) * scale)
                    Rectangle().fill(Category.engagement.color).frame(width: CGFloat(spending.engagementCents) * scale)
                }
                .clipShape(Capsule())
            }
            .overlay {
                if total > plannedCents { Capsule().strokeBorder(Theme.warn, lineWidth: 1) }
            }
        }
        .frame(height: 8)
    }

    private var leftText: String {
        switch stage {
        case .upcoming: return specialBills ?? String(localized: "Regular bills + everyday money", bundle: AppLanguage.bundle)
        case .now, .finished: return String(localized: "of \(Money.format(plannedCents)) planned", bundle: AppLanguage.bundle)
        }
    }

    private var rightText: String {
        switch stage {
        case .upcoming: return String(localized: "Coming up", bundle: AppLanguage.bundle)
        case .now: return diff >= 0 ? "\(Money.format(diff, alwaysShowCents: true)) left" : "\(Money.format(-diff, alwaysShowCents: true)) over"
        case .finished: return diff >= 0 ? "\(Money.format(diff, alwaysShowCents: true)) under" : "\(Money.format(-diff, alwaysShowCents: true)) over"
        }
    }

    private var rightColor: Color {
        if stage == .upcoming { return Theme.secondary }
        return diff >= 0 ? Theme.mint : Theme.warn
    }

    private var accessibilityText: String {
        let name = MonthKey.title(of: spending.monthKey)
        if stage == .upcoming { return "\(name), coming up, \(Money.format(plannedCents)) planned. \(specialBills ?? "")" }
        return "\(name), spent \(Money.format(total, alwaysShowCents: true)) of \(Money.format(plannedCents)) planned, \(rightText)"
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
                    .buttonStyle(.pressable)
                    .listRowBackground(Color.white.opacity(0.06))
            }
            .onDelete { offsets in
                let doomed = offsets.map { items[$0] }
                for e in doomed { BillPayments.delete(e, in: context) }
            }
            if items.isEmpty {
                Text("No expenses on this day.").foregroundStyle(Theme.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(GlowBackground())
        .navigationTitle(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().locale(AppLanguage.locale)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 90) }
        .sheet(item: $editing) { e in
            AddExpenseView(editing: e)
                .presentationBackground(Theme.base)
        }
    }
}
