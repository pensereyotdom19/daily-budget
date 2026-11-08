import SwiftUI
import SwiftData

struct PlanSummaryRoute: Hashable {}

/// How the plan went: days on budget, spending against the plan, savings and the best month.
struct PlanSummaryView: View {
    @Query(sort: \Expense.date) private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var settingsList: [BudgetSettings]
    @State private var startingNew = false

    private var settings: BudgetSettings? { settingsList.first }
    private var months: [String] { settings?.planMonths ?? [] }
    private var calc: BudgetCalculator { BudgetCalculator(expenses: expenses, settings: settings, incomes: incomes) }
    private var ended: Bool { BudgetCalculator.planHasEnded(planMonths: months, today: .now) }

    var body: some View {
        let calc = self.calc
        let s = calc.planSummary(planMonths: months, today: .now, streakStart: settings?.streakStartDate ?? .now)
        let savings = settings?.savingsCents(calc, incomes: incomes) ?? 0
        ScrollView {
            VStack(spacing: 14) {
                ScreenHeader(caption: ended ? "Plan finished" : "Plan so far", title: "Summary")
                daysCard(s)
                HStack(spacing: 12) {
                    tile("Spent", Money.format(s.totalSpentCents, alwaysShowCents: true),
                         "of \(Money.format(settings?.totalCents ?? 0)) total", Theme.ink)
                    tile("Saved", Money.format(savings, alwaysShowCents: true), "emergency savings", Theme.sky)
                }
                VStack(spacing: 0) {
                    row("Everyday", s.livingSpentCents, of: s.livingPlannedCents, Theme.mint)
                    Divider().overlay(Theme.ink.opacity(0.14))
                    row("Bills", s.billsCents, of: nil, Category.bills.color)
                    Divider().overlay(Theme.ink.opacity(0.14))
                    row("Engagement", s.engagementCents, of: nil, Category.engagement.color)
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
                .glassCard()
                if let best = s.bestMonth {
                    HStack(spacing: 12) {
                        Image(systemName: "trophy.fill").font(.system(size: 22)).foregroundStyle(Theme.warn)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Best month").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                            Text(MonthKey.title(of: best)).font(.headline)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .glassCard(radius: 22)
                }
                Button { startingNew = true } label: {
                    Label("Start a new plan", systemImage: "calendar.badge.plus")
                        .font(.headline).foregroundStyle(Theme.base)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Theme.accentGradient, in: Capsule())
                }
                .buttonStyle(.pressable)
                .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(GlowBackground())
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $startingNew) { NewPlanView() }
    }

    private func daysCard(_ s: BudgetCalculator.PlanSummary) -> some View {
        let fraction = s.daysCounted > 0 ? Double(s.daysOnBudget) / Double(s.daysCounted) : 0
        return HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Theme.ink.opacity(0.16), lineWidth: 12)
                Circle().trim(from: 0, to: fraction)
                    .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((fraction * 100).rounded()))%").font(Theme.rounded(24))
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 4) {
                Text("DAYS ON BUDGET").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                Text("\(s.daysOnBudget) of \(s.daysCounted)").font(Theme.rounded(26))
                Text("Days you spent no more than that day's limit.")
                    .font(.caption).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .glassCard(radius: 30)
    }

    private func tile(_ title: LocalizedStringKey, _ value: String, _ note: LocalizedStringKey, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
            Text(value).font(Theme.rounded(22)).foregroundStyle(color).minimumScaleFactor(0.6).lineLimit(1)
            Text(note).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(radius: 22)
    }

    private func row(_ title: LocalizedStringKey, _ cents: Int, of planned: Int?, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(Money.format(cents, alwaysShowCents: true)).font(Theme.rounded(16))
                if let planned {
                    Text("of \(Money.format(planned))").font(.caption).foregroundStyle(Theme.secondary)
                }
            }
        }
        .padding(.vertical, 11)
    }
}
