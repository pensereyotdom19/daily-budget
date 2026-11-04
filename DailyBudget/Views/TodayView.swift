import SwiftUI
import SwiftData

struct TodayView: View {
    var onSeeAll: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query private var settingsList: [BudgetSettings]
    @Query(sort: \Bill.sortOrder) private var bills: [Bill]
    @State private var editing: Expense?
    @State private var justAdded: Expense?
    @State private var addedCount = 0
    @State private var toastTask: Task<Void, Never>?

    private var settings: BudgetSettings? { settingsList.first }
    private var calc: BudgetCalculator { BudgetCalculator(expenses: expenses, settings: settings) }

    /// Today's expenses, without bill payments (those live in History and the month screens).
    private var todaysExpenses: [Expense] {
        expenses.filter { Calendar.current.isDateInToday($0.date) && $0.billID == nil }
    }

    private var billsPaidTodayCents: Int {
        expenses.filter { Calendar.current.isDateInToday($0.date) && $0.billID != nil }
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
            let due = bills.filter { $0.isDue(in: month) && !$0.isPaid(in: month) }
                .sorted { $0.amountCents > $1.amountCents }
            if let b = due.first { return (b, month) }
        }
        return nil
    }

    var body: some View {
        let today = calc.summary(on: .now)
        let streak = calc.streak(endingOn: .now, since: settings?.streakStartDate ?? .now)

        NavigationStack {
        ScrollView {
            VStack(spacing: 14) {
                HStack(alignment: .bottom) {
                    ScreenHeader(caption: Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()), title: "Today")
                    if streak > 0 {
                        Label("\(streak) day\(streak == 1 ? "" : "s") on budget", systemImage: "checkmark")
                            .font(.footnote.weight(.semibold))
                            .labelStyle(StreakLabelStyle())
                            .padding(.horizontal, 12).frame(height: 34)
                            .glassCard(radius: 17)
                            .fixedSize()
                    }
                }

                NavigationLink(value: Calendar.current.startOfDay(for: .now)) {
                    ringCard(today)
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Shows today's expenses")

                HStack(spacing: 12) {
                    NavigationLink(value: MonthRoute(monthKey: MonthKey.key(for: .now))) {
                        statCard(title: "\(MonthKey.title(of: MonthKey.key(for: .now)).uppercased()) LEFT",
                                 value: Money.format(calc.monthLeftCents(inMonthOf: .now), alwaysShowCents: true),
                                 note: "of \(Money.format(settings?.livingMonthlyCents ?? 0)) living money",
                                 noteColor: Theme.secondary)
                    }
                    .buttonStyle(.pressable)
                    if let next = nextBill {
                        NavigationLink(value: MonthRoute(monthKey: next.month)) {
                            statCard(title: "NEXT BILL",
                                     value: Money.format(next.bill.amountCents),
                                     note: "\(next.bill.name) · \(MonthKey.title(of: next.month))",
                                     noteColor: Theme.warn)
                        }
                        .buttonStyle(.pressable)
                    } else {
                        NavigationLink(value: MonthRoute(monthKey: MonthKey.key(for: .now))) {
                            statCard(title: "NEXT BILL", value: "None", note: "All bills paid", noteColor: Theme.secondary)
                        }
                        .buttonStyle(.pressable)
                    }
                }

                if !quickItems.isEmpty { quickAddRow }

                HStack(alignment: .firstTextBaseline) {
                    Text("Today's spending").font(.title3.weight(.bold))
                    Spacer()
                    Button("See all", action: onSeeAll)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 4).padding(.top, 4)

                if billsPaidTodayCents > 0 {
                    NavigationLink(value: MonthRoute(monthKey: MonthKey.key(for: .now), category: .bills)) {
                        HStack(spacing: 10) {
                            Image(systemName: Category.bills.symbol).foregroundStyle(Category.bills.color)
                            Text("Bills paid today \(Money.format(billsPaidTodayCents, alwaysShowCents: true))")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 14).frame(height: 40)
                        .glassCard(radius: 20)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityHint("Shows this month's bills")
                }

                if todaysExpenses.isEmpty {
                    Text("Nothing yet today. Tap + to add an expense.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(20)
                        .glassCard()
                } else {
                    VStack(spacing: 0) {
                        ForEach(todaysExpenses) { e in
                            Button { editing = e } label: { ExpenseRow(expense: e) }
                                .buttonStyle(.pressable)
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") { editing = e }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        BillPayments.delete(e, in: context)
                                    }
                                }
                            if e.id != todaysExpenses.last?.id { Divider().overlay(Color.white.opacity(0.14)) }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 4)
                    .glassCard()
                    Text("Tap an expense to edit it. Press and hold to delete.")
                        .font(.caption).foregroundStyle(Theme.secondary)
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
        .sheet(item: $editing) { e in
            AddExpenseView(editing: e)
                .presentationBackground(Theme.base)
        }
        }
    }

    private var quickAddRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("QUICK ADD").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                Text("Tap to add it now").font(.caption).foregroundStyle(Theme.secondary.opacity(0.7))
            }
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
        .padding(.top, 2)
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
        .glassCard(radius: 25)
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

    private func ringCard(_ today: BudgetCalculator.DaySummary) -> some View {
        let fraction = today.limitCents > 0 ? max(0, Double(today.leftCents) / Double(today.limitCents)) : 0
        return HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.16), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: min(1, fraction))
                    .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: fraction)
                VStack(spacing: 0) {
                    Text(Money.format(today.leftCents, alwaysShowCents: true))
                        .font(Theme.rounded(28))
                        .foregroundStyle(today.isOver ? Theme.warn : .white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(today.isOver ? "OVER TODAY" : "LEFT TODAY")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.secondary)
                }
                .padding(18)
            }
            .frame(width: 132, height: 132)
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 10) {
                labeled("DAILY LIMIT", Money.format(today.limitCents, alwaysShowCents: true))
                labeled("SPENT", Money.format(today.spentCents, alwaysShowCents: true))
                Text("Unused money rolls into tomorrow")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .glassCard(radius: 30)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
            Text(value).font(Theme.rounded(20))
        }
    }

    private func statCard(title: String, value: String, note: String, noteColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold)).foregroundStyle(Theme.secondary)
            }
            Text(value).font(Theme.rounded(24))
            Text(note).font(.caption).foregroundStyle(noteColor).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(radius: 22)
    }
}

/// A small glass button: category icon, name and price.
struct QuickAddChip: View {
    let item: QuickAdd.Item

    var body: some View {
        HStack(spacing: 8) {
            CategoryIcon(category: item.category, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(.footnote.weight(.semibold)).lineLimit(1)
                Text(Money.format(item.cents, alwaysShowCents: true))
                    .font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.secondary)
            }
        }
        .padding(.leading, 9).padding(.trailing, 14)
        .frame(height: 48)
        .glassCard(radius: 24)
    }
}

struct StreakLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(Theme.mint)
            configuration.title
        }
    }
}

struct ExpenseRow: View {
    let expense: Expense

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: expense.category, size: 40, symbol: expense.iconSymbol)
            VStack(alignment: .leading, spacing: 1) {
                Text(expense.note.isEmpty ? expense.category.title : expense.note)
                    .font(.subheadline.weight(.semibold))
                Text("\(expense.category.title) · \(expense.date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Text(Money.format(expense.amountCents, alwaysShowCents: true))
                .font(Theme.rounded(16))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
