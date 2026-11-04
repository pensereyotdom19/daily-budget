import Foundation

extension BudgetCalculator {
    /// Builds a calculator from the saved expenses and plan settings.
    init(expenses: [Expense], settings: BudgetSettings?) {
        self.init(
            entries: expenses.map { Entry(date: $0.date, cents: $0.amountCents, countsAsLiving: $0.category.countsAsLiving) },
            livingMonthlyCents: settings?.livingMonthlyCents ?? 9_200
        )
    }
}

extension BudgetSettings {
    var planMonths: [String] { MonthKey.range(start: startMonth, count: monthCount) }
    var planStartDate: Date { MonthKey.firstDay(of: startMonth) ?? .now }
    /// First day the streak may count: the later of plan start and first app use.
    var streakStartDate: Date { BudgetCalculator.streakStart(planStart: planStartDate, firstOpened: firstOpenedAt) }
}
