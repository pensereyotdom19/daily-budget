import SwiftUI
import SwiftData

struct TodayView: View {
    var onSeeAll: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query private var settingsList: [BudgetSettings]
    @Query(sort: \Bill.sortOrder) private var bills: [Bill]

    private var settings: BudgetSettings? { settingsList.first }
    private var calc: BudgetCalculator { BudgetCalculator(expenses: expenses, settings: settings) }

    private var todaysExpenses: [Expense] {
        expenses.filter { Calendar.current.isDateInToday($0.date) }
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

                ringCard(today)

                HStack(spacing: 12) {
                    statCard(title: "\(MonthKey.title(of: MonthKey.key(for: .now)).uppercased()) LEFT",
                             value: Money.format(calc.monthLeftCents(inMonthOf: .now), alwaysShowCents: true),
                             note: "of \(Money.format(settings?.livingMonthlyCents ?? 0)) living money",
                             noteColor: Theme.secondary)
                    if let next = nextBill {
                        statCard(title: "NEXT BILL",
                                 value: Money.format(next.bill.amountCents),
                                 note: "\(next.bill.name) · \(MonthKey.title(of: next.month))",
                                 noteColor: Theme.warn)
                    } else {
                        statCard(title: "NEXT BILL", value: "None", note: "All bills paid", noteColor: Theme.secondary)
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Today's spending").font(.title3.weight(.bold))
                    Spacer()
                    Button("See all", action: onSeeAll)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 4).padding(.top, 4)

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
                            ExpenseRow(expense: e)
                                .contextMenu {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        context.delete(e)
                                    }
                                }
                            if e.id != todaysExpenses.last?.id { Divider().overlay(Color.white.opacity(0.14)) }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 4)
                    .glassCard()
                    Text("Press and hold an expense to delete it.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
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
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
            Text(value).font(Theme.rounded(24))
            Text(note).font(.caption).foregroundStyle(noteColor).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(radius: 22)
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
            CategoryIcon(category: expense.category)
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
