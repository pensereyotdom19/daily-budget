import Foundation

/// How often a bill in a new plan is due.
enum BillFrequency: String, CaseIterable, Identifiable {
    case monthly, every3Months, once
    var id: String { rawValue }

    /// The months of `planMonths` this bill is due in. `onceIndex` picks the month for `.once`.
    func dueMonths(in planMonths: [String], onceIndex: Int = 0) -> [String] {
        switch self {
        case .monthly: return planMonths
        case .every3Months: return planMonths.enumerated().filter { $0.offset % 3 == 0 }.map(\.element)
        case .once: return planMonths.indices.contains(onceIndex) ? [planMonths[onceIndex]] : Array(planMonths.prefix(1))
        }
    }

    /// Guesses how an existing bill repeats in its plan. Nil for one-off bills (not carried over).
    static func guess(dueMonths: [String], planMonths: [String]) -> BillFrequency? {
        let due = dueMonths.filter { planMonths.contains($0) }.sorted()
        guard !due.isEmpty else { return nil }
        if due == planMonths { return .monthly }
        if due.count > 1, due == BillFrequency.every3Months.dueMonths(in: planMonths) { return .every3Months }
        return nil
    }
}

enum PlanMath {
    /// The month a new plan should start: the month after the current plan, or this month if that has passed.
    static func suggestedStart(currentPlanMonths: [String], today: Date, calendar: Calendar = .current) -> String {
        let now = MonthKey.key(for: today, calendar: calendar)
        guard let last = currentPlanMonths.last else { return now }
        let next = MonthKey.range(start: last, count: 2)[1]
        return max(next, now)
    }

    /// Living money for every month + every bill due + engagement.
    static func plannedTotal(livingMonthlyCents: Int, monthCount: Int, engagementCents: Int,
                             bills: [(cents: Int, dueCount: Int)]) -> Int {
        livingMonthlyCents * monthCount + engagementCents + bills.reduce(0) { $0 + $1.cents * $1.dueCount }
    }
}
