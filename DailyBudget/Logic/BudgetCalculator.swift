import Foundation

/// All budget math lives here, separate from the UI so it can be unit tested.
///
/// Rules:
/// 1. Today's limit = living money left this month ÷ days left in the month (including today).
///    Unspent money rolls into the following days; overspending lowers them.
/// 2. Only everyday categories count against living money (not Bills or Engagement).
/// 3. A day is "over" when its living spending is more than its limit.
/// 4. Living money left at the end of a finished month goes to emergency savings.
struct BudgetCalculator {
    struct Entry {
        var date: Date
        var cents: Int
        var countsAsLiving: Bool
    }

    struct DaySummary: Identifiable {
        var day: Date
        var limitCents: Int
        var spentCents: Int
        var id: Date { day }
        var leftCents: Int { limitCents - spentCents }
        var isOver: Bool { spentCents > limitCents }
    }

    var entries: [Entry]
    var livingMonthlyCents: Int
    var calendar: Calendar = .current

    // MARK: - Basic sums

    private func livingSpent(from start: Date, to end: Date) -> Int {
        entries.lazy
            .filter { $0.countsAsLiving && $0.date >= start && $0.date < end }
            .reduce(0) { $0 + $1.cents }
    }

    private func monthInterval(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .month, for: date)!
    }

    func livingSpent(inMonthOf date: Date) -> Int {
        let m = monthInterval(containing: date)
        return livingSpent(from: m.start, to: m.end)
    }

    func monthLeftCents(inMonthOf date: Date) -> Int {
        livingMonthlyCents - livingSpent(inMonthOf: date)
    }

    // MARK: - Daily limit

    func limitCents(on date: Date) -> Int {
        let dayStart = calendar.startOfDay(for: date)
        let month = monthInterval(containing: date)
        let spentBefore = livingSpent(from: month.start, to: dayStart)
        let remainingMoney = max(0, livingMonthlyCents - spentBefore)
        let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        let dayOfMonth = calendar.component(.day, from: date)
        let daysLeft = max(1, daysInMonth - dayOfMonth + 1)
        return remainingMoney / daysLeft
    }

    func spentCents(on date: Date) -> Int {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return livingSpent(from: start, to: end)
    }

    func summary(on date: Date) -> DaySummary {
        DaySummary(day: calendar.startOfDay(for: date),
                   limitCents: limitCents(on: date),
                   spentCents: spentCents(on: date))
    }

    /// Days of the month containing `date`, up to and including `date`, newest first.
    func daySummaries(inMonthOf date: Date) -> [DaySummary] {
        let month = monthInterval(containing: date)
        var result: [DaySummary] = []
        var day = month.start
        let last = calendar.startOfDay(for: date)
        while day <= last {
            result.append(summary(on: day))
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result.reversed()
    }

    // MARK: - Streak and savings

    /// Consecutive days on or under budget, counting back from `today` (not before `since`).
    func streak(endingOn today: Date, since start: Date) -> Int {
        var count = 0
        var day = calendar.startOfDay(for: today)
        let floor = calendar.startOfDay(for: start)
        while day >= floor, count < 400 {
            if summary(on: day).isOver { break }
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    /// The streak counts from the later of the plan start and the first time the app was opened,
    /// so days before you started using the app don't count as "on budget".
    static func streakStart(planStart: Date, firstOpened: Date?) -> Date {
        guard let firstOpened else { return planStart }
        return max(planStart, firstOpened)
    }

    /// Sum of leftover living money from plan months that have fully ended before `today`.
    func emergencySavingsCents(planMonths: [String], today: Date) -> Int {
        let currentKey = MonthKey.key(for: today, calendar: calendar)
        return planMonths
            .filter { $0 < currentKey }
            .compactMap { MonthKey.firstDay(of: $0, calendar: calendar) }
            .map { max(0, monthLeftCents(inMonthOf: $0)) }
            .reduce(0, +)
    }
}
