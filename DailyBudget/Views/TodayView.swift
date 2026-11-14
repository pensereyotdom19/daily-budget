import SwiftUI
import SwiftData

struct TodayView: View {
    var onSeeAll: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(SyncManager.self) private var sync
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var settingsList: [BudgetSettings]
    @Query(sort: \Bill.sortOrder) private var bills: [Bill]
    @State private var editing: Expense?
    @State private var editingIncome: Income?
    @State private var justAdded: Expense?
    @State private var affording = false
    @State private var addedCount = 0
    @State private var toastTask: Task<Void, Never>?

    private var settings: BudgetSettings? { settingsList.first }
    private var calc: BudgetCalculator { BudgetCalculator(expenses: expenses, settings: settings, incomes: incomes) }

    /// Today's expenses, without bill payments (those live in History and the month screens).
    /// Extra income dated today, shown in green above today's expenses.
    private var todaysIncomes: [Income] {
        incomes.filter { Calendar.current.isDateInToday($0.date) }.sorted { $0.date > $1.date }
    }

    private var todaysExpenses: [Expense] {
        expenses.filter { Calendar.current.isDateInToday($0.date) && $0.category != .bills }
    }

    private var billsPaidTodayCents: Int {
        expenses.filter { Calendar.current.isDateInToday($0.date) && $0.category == .bills }
            .reduce(0) { $0 + $1.amountCents }
    }

    /// One-tap buttons for what you log most often.
    private var quickItems: [QuickAdd.Item] {
        QuickAdd.suggestions(from: expenses.filter { $0.billID == nil }
            .map { QuickAdd.Past(category: $0.category, note: $0.note, cents: $0.amountCents, date: $0.date) })
    }

    /// The nearest unpaid bill from this month onward, biggest first within the same month.
    private var nextBill: (bill: Bill, month: String)? {
        let current = MonthKey.key(for: .now)
        let months = (settings?.planMonths ?? []).filter { $0 >= current }
        for month in months {
            // Bills with a due day come in date order; the rest after them, biggest first.
            let due = bills.filter { $0.isDue(in: month) && !$0.isPaid(in: month) }
                .sorted { a, b in
                    switch (a.dueDay, b.dueDay) {
                    case let (x?, y?): return x < y
                    case (_?, nil): return true
                    case (nil, _?): return false
                    default: return a.amountCents > b.amountCents
                    }
                }
            if let b = due.first { return (b, month) }
        }
        return nil
    }

    var body: some View {
        // Built once per redraw; every card below reads from it.
        let calc = self.calc
        let today = calc.summary(on: .now)
        let streak = calc.streak(endingOn: .now, since: settings?.streakStartDate ?? .now)

        NavigationStack {
        ScrollView {
            VStack(spacing: 16) {
                HStack(alignment: .bottom) {
                    ScreenHeader(caption: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.locale)), title: "Today")
                    if sync.isSignedIn { syncBadge }
                }

                if let expiry = AppExpiry.date, AppExpiry.daysLeft(until: expiry) <= 1 {
                    HStack(spacing: 10) {
                        Image(systemName: "hourglass").foregroundStyle(Theme.warn)
                        Text(AppExpiry.daysLeft(until: expiry) <= 0
                             ? "This install stops opening today. Run it from Xcode on your Mac to get 7 more days."
                             : "This install stops opening tomorrow. Run it from Xcode on your Mac to get 7 more days.")
                            .font(.footnote.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .glassCard(radius: 20)
                }

                if BudgetCalculator.planHasEnded(planMonths: settings?.planMonths ?? [], today: .now) {
                    NavigationLink(value: PlanSummaryRoute()) {
                        HStack(spacing: 10) {
                            Image(systemName: "flag.checkered").foregroundStyle(Theme.warn)
                            Text("Your plan has ended. See how it went and start a new one.")
                                .font(.footnote.weight(.semibold)).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                        }
                        .padding(14)
                        .glassCard(radius: 20)
                    }
                    .buttonStyle(.pressable)
                }

                NavigationLink(value: Calendar.current.startOfDay(for: .now)) {
                    ringCard(today, streak: streak)
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Shows today's expenses")

                VStack(spacing: 0) {
                    NavigationLink(value: MonthRoute(monthKey: MonthKey.key(for: .now))) {
                        statCard(title: "\(MonthKey.title(of: MonthKey.key(for: .now))) left",
                                 value: Money.format(calc.monthLeftCents(inMonthOf: .now), alwaysShowCents: true),
                                 note: livingNote(calc),
                                 noteColor: Theme.secondary)
                    }
                    .buttonStyle(.pressable)
                    Divider().overlay(Theme.rule).padding(.leading, 14)
                    if let next = nextBill {
                        NavigationLink(value: MonthRoute(monthKey: next.month)) {
                            statCard(title: "Next bill",
                                     value: Money.format(next.bill.amountCents),
                                     note: "\(next.bill.name) · \(next.bill.dueDay.flatMap { BillSchedule.dueDate(month: next.month, day: $0) }.map { $0.formatted(.dateTime.month(.abbreviated).day().locale(AppLanguage.locale)) } ?? MonthKey.title(of: next.month))",
                                     noteColor: Theme.secondary)
                        }
                        .buttonStyle(.pressable)
                    } else {
                        NavigationLink(value: MonthRoute(monthKey: MonthKey.key(for: .now))) {
                            statCard(title: "Next bill", value: String(localized: "None", bundle: AppLanguage.bundle), note: "All bills paid", noteColor: Theme.secondary)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .glassCard()

                let warnings = calc.limitStatuses(limits: settings?.categoryLimits ?? [:], on: .now).filter { $0.level != .ok }
                if !warnings.isEmpty { limitWarnings(warnings) }

                Button { affording = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "questionmark.circle").foregroundStyle(Theme.mint)
                        Text("Can I afford it?")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(Theme.secondary)
                    }
                    .font(.body)
                    .padding(.horizontal, 14).frame(height: 48)
                    .glassCard()
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Check a price before you buy")

                if !quickItems.isEmpty { quickAddRow }

                HStack(alignment: .firstTextBaseline) {
                    Text("Today's spending").font(.headline)
                    Spacer()
                    Button("See all", action: onSeeAll)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.mint)
                }
                .padding(.horizontal, 4).padding(.top, 4)

                if billsPaidTodayCents > 0 {
                    NavigationLink(value: MonthRoute(monthKey: MonthKey.key(for: .now), category: .bills)) {
                        HStack(spacing: 10) {
                            Image(systemName: Category.bills.symbol).foregroundStyle(Theme.mint)
                            Text("Bills paid today \(Money.format(billsPaidTodayCents, alwaysShowCents: true))")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 14).frame(height: 44)
                        .glassCard()
                    }
                    .buttonStyle(.pressable)
                    .accessibilityHint("Shows this month's bills")
                }

                if todaysExpenses.isEmpty && todaysIncomes.isEmpty {
                    Text("Nothing yet today. Tap + to add an expense.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(20)
                        .glassCard()
                } else {
                    VStack(spacing: 0) {
                        ForEach(todaysIncomes) { i in
                            Button { editingIncome = i } label: { IncomeRow(income: i, size: 32) }
                                .buttonStyle(.pressable)
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") { editingIncome = i }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        context.delete(i)
                                        try? context.save()
                                    }
                                }
                            if i.id != todaysIncomes.last?.id || !todaysExpenses.isEmpty { Divider().overlay(Theme.rule).padding(.leading, 44) }
                        }
                        ForEach(todaysExpenses) { e in
                            Button { editing = e } label: { ExpenseRow(expense: e) }
                                .buttonStyle(.pressable)
                                .expenseSwipe(e)
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") { editing = e }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        DeleteUndo.shared.delete(e, in: context)
                                    }
                                }
                            if e.id != todaysExpenses.last?.id { Divider().overlay(Theme.rule).padding(.leading, 44) }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 2)
                    .glassCard()
                    // A tip for the first days only; after that the screen stays quiet.
                    if expenses.count < 12 {
                        Text("Tap to edit. Swipe left to delete, right to add it again.")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            if let e = justAdded { addedToast(e) }
        }
        .sensoryFeedback(.success, trigger: addedCount)
        .background(GlowBackground())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: MonthRoute.self) { route in
            MonthDetailView(route: route)
        }
        .navigationDestination(for: Date.self) { day in
            DayDetailView(day: day)
        }
        .navigationDestination(for: AccountRoute.self) { _ in AccountView() }
        .navigationDestination(for: PlanSummaryRoute.self) { _ in PlanSummaryView() }
        .sheet(isPresented: $affording) {
            AffordView().presentationBackground(Theme.base)
        }
        .sheet(item: $editing) { e in
            AddExpenseView(editing: e)
                .presentationBackground(Theme.base)
        }
        .sheet(item: $editingIncome) { i in
            AddExpenseView(editingIncome: i)
                .presentationBackground(Theme.base)
        }
        }
    }

    private var quickAddRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick add").font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
                .padding(.leading, 4)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(quickItems) { item in
                        Button { quickAdd(item) } label: { QuickAddChip(item: item) }
                            .buttonStyle(.pressable)
                            .accessibilityLabel("Add \(item.title), \(Money.format(item.cents, alwaysShowCents: true))")
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    /// "of $192 living money · +$100 extra" when extra income went into this month.
    private func livingNote(_ calc: BudgetCalculator) -> LocalizedStringKey {
        let budget = Money.format(calc.livingBudget(inMonthOf: .now))
        let extra = calc.extraLivingByMonth[MonthKey.key(for: .now)] ?? 0
        if extra > 0 { return "of \(budget) · +\(Money.format(extra)) extra" }
        return "of \(budget) living money"
    }

    private func addedToast(_ e: Expense) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.mint)
            Text("Added \(e.note.isEmpty ? e.category.title : e.note) \(Money.format(e.amountCents, alwaysShowCents: true))")
                .lineLimit(1)
            Spacer(minLength: 6)
            Button("Undo") { undo(e) }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.mint)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 16).frame(height: 50)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, 18)
        .padding(.bottom, 96)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func quickAdd(_ item: QuickAdd.Item) {
        let e = Expense(amountCents: item.cents, category: item.category, note: item.note, date: .now)
        context.insert(e)
        try? context.save()
        addedCount += 1
        withAnimation(.snappy) { justAdded = e }
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { justAdded = nil }
        }
    }

    private func undo(_ e: Expense) {
        toastTask?.cancel()
        withAnimation(.snappy) { justAdded = nil }
        BillPayments.delete(e, in: context)
    }

    /// Categories at 80% of their monthly limit or over it.
    private func limitWarnings(_ list: [BudgetCalculator.LimitStatus]) -> some View {
        VStack(spacing: 8) {
            ForEach(list) { s in
                let c = Category(rawValue: s.category) ?? .other
                NavigationLink(value: MonthRoute(monthKey: MonthKey.key(for: .now), category: c)) {
                    HStack(spacing: 10) {
                        CategoryIcon(category: c, size: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.level == .over
                                 ? "\(c.title): \(Money.format(-s.leftCents, alwaysShowCents: true)) over this month's limit"
                                 : "\(c.title): \(Money.format(s.leftCents, alwaysShowCents: true)) left of \(Money.format(s.limitCents))")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(s.level == .over ? Theme.warn : Theme.ink)
                            GeometryReader { geo in
                                Rectangle().fill(s.level == .over ? Theme.warn : c.color)
                                    .frame(width: geo.size.width * min(1, CGFloat(s.spentCents) / CGFloat(max(1, s.limitCents))))
                            }
                            .frame(height: 5)
                            .background(Theme.ink.opacity(0.1), in: Rectangle())
                        }
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(Theme.secondary)
                    }
                    .padding(12)
                    .glassCard(radius: 18)
                }
                .buttonStyle(.pressable)
            }
        }
    }

    /// Backup status: synced, waiting to upload, syncing or a problem. Tap for details.
    private var syncBadge: some View {
        let state: (symbol: String, color: Color, label: String) = {
            switch sync.status {
            case .syncing: return ("arrow.triangle.2.circlepath.icloud", Theme.sky, String(localized: "Backing up", bundle: AppLanguage.bundle))
            case .failed: return ("exclamationmark.icloud.fill", Theme.warn, String(localized: "Backup problem", bundle: AppLanguage.bundle))
            default:
                return sync.pending > 0
                    ? ("icloud.fill", Theme.secondary, String(localized: "\(sync.pending) changes waiting to back up", bundle: AppLanguage.bundle))
                    : ("checkmark.icloud.fill", Theme.mint, String(localized: "Backed up", bundle: AppLanguage.bundle))
            }
        }()
        return NavigationLink(value: AccountRoute()) {
            Image(systemName: state.symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(state.color)
                .symbolEffect(.pulse, isActive: sync.status == .syncing)
                .frame(width: 34, height: 34)
                .glassCard(radius: 17)
                .overlay(alignment: .topTrailing) {
                    if sync.pending > 0 && sync.status != .syncing {
                        Text("\(min(sync.pending, 99))")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.base)
                            .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                            .background(Theme.warn, in: Rectangle())
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(state.label)
    }

    /// The top of Today: what's left today as the one big number, a thin bar, then
    /// the daily limit, what's spent and the streak in one row.
    private func ringCard(_ today: BudgetCalculator.DaySummary, streak: Int) -> some View {
        let fraction = today.limitCents > 0 ? max(0, Double(today.leftCents) / Double(today.limitCents)) : 0
        return VStack(alignment: .leading, spacing: 0) {
            Text(today.isOver ? "Over today" : "Left to spend today")
                .font(.subheadline).foregroundStyle(Theme.secondary)
            Text(Money.format(today.isOver ? -today.leftCents : today.leftCents, alwaysShowCents: true))
                .font(.system(size: 56, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(today.isOver ? Theme.warn : Theme.ink)
                .minimumScaleFactor(0.5).lineLimit(1)
                .padding(.bottom, 10)
            GeometryReader { geo in
                Capsule().fill(today.isOver ? Theme.warn : Theme.mint)
                    .frame(width: max(6, geo.size.width * min(1, today.isOver ? 1 : fraction)))
                    .animation(.snappy, value: fraction)
            }
            .frame(height: 6)
            .background(Theme.rule, in: Capsule())
            .padding(.bottom, 14)
            HStack(spacing: 0) {
                labeled("Daily limit", Money.format(today.limitCents, alwaysShowCents: true))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Theme.rule).frame(width: 1, height: 34)
                labeled("Spent", Money.format(today.spentCents, alwaysShowCents: true))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14)
                if streak > 0 {
                    Rectangle().fill(Theme.rule).frame(width: 1, height: 34)
                    labeled("Streak", String(localized: "\(streak) days", bundle: AppLanguage.bundle))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 14)
                }
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func labeled(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.secondary)
            Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    /// A list row: title with a small note under it, the amount on the right, and a chevron.
    private func statCard(title: LocalizedStringKey, value: String, note: LocalizedStringKey, noteColor: Color) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body)
                Text(note).font(.caption).foregroundStyle(noteColor).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary.opacity(0.7))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
    }

}

/// A small pill: what you buy often and its price. One tap adds it.
struct QuickAddChip: View {
    let item: QuickAdd.Item

    var body: some View {
        HStack(spacing: 5) {
            Text(item.title).lineLimit(1)
            Text(Money.format(item.cents, alwaysShowCents: true))
                .monospacedDigit().foregroundStyle(Theme.secondary)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Theme.card, in: Capsule())
    }
}

struct StreakLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(Theme.highlight)
            configuration.title
        }
    }
}

struct ExpenseRow: View {
    let expense: Expense

    var body: some View {
        HStack(spacing: 12) {
            ExpenseIcon(expense: expense, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(expense.note.isEmpty ? expense.category.title : expense.note)
                    .font(.body)
                Text("\(expense.category.title) · \(expense.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: AppLanguage.locale)))")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Text(Money.format(expense.amountCents, alwaysShowCents: true))
                .font(.system(size: 17, weight: .semibold)).monospacedDigit()
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

/// A straight horizontal line across its frame.
struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
