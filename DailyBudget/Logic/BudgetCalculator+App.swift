import Foundation

extension BudgetCalculator {
    /// Builds a calculator from the saved expenses, plan settings and extra income.
    init(expenses: [Expense], settings: BudgetSettings?, incomes: [Income] = []) {
        self.init(
            entries: expenses.map { Entry(date: $0.date, cents: $0.amountCents, countsAsLiving: $0.category.countsAsLiving,
                                         isEngagement: $0.category == .engagement) },
            livingMonthlyCents: settings?.livingMonthlyCents ?? 9_200,
            extraLivingByMonth: Income.byMonth(incomes, target: .living)
        )
    }
}

extension Income {
    /// Total income per month key for one target.
    static func byMonth(_ incomes: [Income], target: IncomeTarget, calendar: Calendar = .current) -> [String: Int] {
        incomes.filter { $0.target == target }
            .reduce(into: [:]) { $0[MonthKey.key(for: $1.date, calendar: calendar), default: 0] += $1.amountCents }
    }

    static func total(_ incomes: [Income], target: IncomeTarget) -> Int {
        incomes.filter { $0.target == target }.reduce(0) { $0 + $1.amountCents }
    }
}

extension BudgetSettings {
    var planMonths: [String] { MonthKey.range(start: startMonth, count: monthCount) }
    var planStartDate: Date { MonthKey.firstDay(of: startMonth) ?? .now }
    /// First day the streak may count: the later of plan start and first app use.
    var streakStartDate: Date { BudgetCalculator.streakStart(planStart: planStartDate, firstOpened: firstOpenedAt) }
    /// Months shown in History: from the first plan's start (kept across new plans) to the current plan's end.
    var historyMonths: [String] {
        let first = min(historyStartMonth ?? startMonth, startMonth)
        guard let last = planMonths.last, let a = MonthKey.components(of: first), let b = MonthKey.components(of: last) else {
            return planMonths
        }
        let count = (b.year * 12 + b.month) - (a.year * 12 + a.month) + 1
        return MonthKey.range(start: first, count: max(1, count))
    }
    /// Emergency savings including income put into savings and what earlier plans saved.
    func savingsCents(_ calc: BudgetCalculator, incomes: [Income], today: Date = .now) -> Int {
        calc.emergencySavingsCents(planMonths: planMonths, today: today,
                                   savingsIncomeByMonth: Income.byMonth(incomes, target: .savings),
                                   savedBeforeCents: savedBeforeCents)
    }
}
