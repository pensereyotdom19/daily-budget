import Foundation

/// All budget math lives here, separate from the UI so it can be unit tested.
///
/// Rules:
/// 1. Today's limit = living money left this month ÷ days left in the month (including today).
///    Unspent money rolls into the following days; overspending lowers them.
/// 2. Only everyday categories count against living money (not Bills or Engagement).
/// 3. A day is "over" when its living spending is more than its limit.
/// 4. Living money left at the end of a finished month goes to emergency savings.
/// 5. Extra income can go to a month's living money (raising its daily limits), to savings, or to Engagement.
struct BudgetCalculator {
    struct Entry {
        var date: Date
        var cents: Int
        var countsAsLiving: Bool
        /// Only used to split non-living spending into bills vs engagement.
        var isEngagement: Bool = false
        /// Category raw name ("coffee"), for category limits and the weekly summary.
        var category: String = ""
    }

    /// What was actually spent in one month, split into the three money groups.
    struct MonthSpending: Identifiable {
        var monthKey: String
        var livingCents = 0
        var billsCents = 0
        var engagementCents = 0
        var id: String { monthKey }
        var totalCents: Int { livingCents + billsCents + engagementCents }
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
    /// Extra income added to a month's living money, by month key ("2026-11").
    var extraLivingByMonth: [String: Int] = [:]

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

    /// Living money for the month containing `date`: the monthly amount plus extra income put there.
    func livingBudget(inMonthOf date: Date) -> Int {
        livingMonthlyCents + (extraLivingByMonth[MonthKey.key(for: date, calendar: calendar)] ?? 0)
    }

    func monthLeftCents(inMonthOf date: Date) -> Int {
        livingBudget(inMonthOf: date) - livingSpent(inMonthOf: date)
    }

    // MARK: - Daily limit

    func limitCents(on date: Date) -> Int {
        let dayStart = calendar.startOfDay(for: date)
        let month = monthInterval(containing: date)
        let spentBefore = livingSpent(from: month.start, to: dayStart)
        let remainingMoney = max(0, livingBudget(inMonthOf: date) - spentBefore)
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

    // MARK: - Month by month

    /// Spending per month for the given month keys, in the same order. Entries outside them are ignored.
    func monthlySpending(months: [String]) -> [MonthSpending] {
        var byMonth = Dictionary(uniqueKeysWithValues: months.map { ($0, MonthSpending(monthKey: $0)) })
        for e in entries {
            let key = MonthKey.key(for: e.date, calendar: calendar)
            guard byMonth[key] != nil else { continue }
            if e.countsAsLiving {
                byMonth[key]!.livingCents += e.cents
            } else if e.isEngagement {
                byMonth[key]!.engagementCents += e.cents
            } else {
                byMonth[key]!.billsCents += e.cents
            }
        }
        return months.compactMap { byMonth[$0] }
    }

    /// Planned spending for a month: living money plus every bill due that month.
    /// (Engagement is a one-off amount set aside, so it isn't part of any single month's plan.)
    static func plannedCents(month: String, livingMonthlyCents: Int, bills: [(cents: Int, dueMonths: [String])]) -> Int {
        bills.filter { $0.dueMonths.contains(month) }.reduce(livingMonthlyCents) { $0 + $1.cents }
    }

    /// Date for a bill payment expense: now if the bill is ticked in its own month,
    /// otherwise noon on the 1st of the bill's month (so it lands in the right month).
    static func billPaymentDate(month: String, now: Date, calendar: Calendar = .current) -> Date {
        if MonthKey.key(for: now, calendar: calendar) == month { return now }
        guard let first = MonthKey.firstDay(of: month, calendar: calendar) else { return now }
        return calendar.date(byAdding: .hour, value: 12, to: first) ?? first
    }

    // MARK: - Streak start

    /// The streak counts from the later of the plan start and the first time the app was opened,
    /// so days before you started using the app don't count as "on budget".
    static func streakStart(planStart: Date, firstOpened: Date?) -> Date {
        guard let firstOpened else { return planStart }
        return max(planStart, firstOpened)
    }

    /// Emergency savings: what earlier plans saved, plus leftover living money from plan months that
    /// have fully ended before `today`, plus extra income put into savings up to this month.
    func emergencySavingsCents(planMonths: [String], today: Date,
                               savingsIncomeByMonth: [String: Int] = [:], savedBeforeCents: Int = 0) -> Int {
        savingsByMonth(planMonths: planMonths, today: today, savingsIncomeByMonth: savingsIncomeByMonth)
            .reduce(savedBeforeCents) { $0 + $1.totalCents }
    }

    struct SavingsMonth: Identifiable, Equatable {
        var monthKey: String
        /// Living money left when the month ended (0 until it ends, never negative).
        var leftoverCents: Int
        var incomeCents: Int
        var id: String { monthKey }
        var totalCents: Int { leftoverCents + incomeCents }
    }

    /// How savings grew, month by month, oldest first: plan months up to now, and any other month
    /// where income went to savings.
    func savingsByMonth(planMonths: [String], today: Date, savingsIncomeByMonth: [String: Int] = [:]) -> [SavingsMonth] {
        let currentKey = MonthKey.key(for: today, calendar: calendar)
        let months = Set(planMonths.filter { $0 <= currentKey })
            // Income from before this plan is already in `savedBeforeCents`.
            .union(savingsIncomeByMonth.keys.filter { $0 <= currentKey && $0 >= (planMonths.first ?? "") })
        return months.sorted().map { key in
            let finished = key < currentKey && planMonths.contains(key)
            let leftover = finished ? MonthKey.firstDay(of: key, calendar: calendar).map { max(0, monthLeftCents(inMonthOf: $0)) } ?? 0 : 0
            return SavingsMonth(monthKey: key, leftoverCents: leftover, incomeCents: savingsIncomeByMonth[key] ?? 0)
        }
    }

    // MARK: - Can I afford it?

    struct WhatIf: Equatable {
        var leftTodayAfter: Int
        var tomorrowLimitNow: Int
        var tomorrowLimitAfter: Int
        var monthLeftAfter: Int
        /// False on the last day of the month: tomorrow starts a fresh month, so today's spending doesn't change it.
        var tomorrowInSameMonth: Bool
        var fitsToday: Bool { leftTodayAfter >= 0 }
    }

    /// What spending `cents` of living money on `date` would do to today, tomorrow and the month.
    func whatIf(spending cents: Int, on date: Date) -> WhatIf {
        var after = self
        after.entries.append(Entry(date: date, cents: cents, countsAsLiving: true))
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
        return WhatIf(leftTodayAfter: after.summary(on: date).leftCents,
                      tomorrowLimitNow: limitCents(on: tomorrow),
                      tomorrowLimitAfter: after.limitCents(on: tomorrow),
                      monthLeftAfter: after.monthLeftCents(inMonthOf: date),
                      tomorrowInSameMonth: calendar.isDate(tomorrow, equalTo: date, toGranularity: .month))
    }

    // MARK: - Plan summary

    struct PlanSummary: Equatable {
        var livingPlannedCents = 0
        var livingSpentCents = 0
        var billsCents = 0
        var engagementCents = 0
        var daysOnBudget = 0
        var daysCounted = 0
        /// The finished month with the most living money left over.
        var bestMonth: String?
        var totalSpentCents: Int { livingSpentCents + billsCents + engagementCents }
    }

    /// How the plan went, counting up to `today` (or the plan's last day if it has ended).
    func planSummary(planMonths: [String], today: Date, streakStart: Date) -> PlanSummary {
        var out = PlanSummary()
        let spending = monthlySpending(months: planMonths)
        let currentKey = MonthKey.key(for: today, calendar: calendar)
        var best: (key: String, left: Int)?
        for m in spending where m.monthKey <= currentKey {
            guard let first = MonthKey.firstDay(of: m.monthKey, calendar: calendar) else { continue }
            out.livingPlannedCents += livingBudget(inMonthOf: first)
            out.livingSpentCents += m.livingCents
            out.billsCents += m.billsCents
            out.engagementCents += m.engagementCents
            if m.monthKey < currentKey {
                let left = monthLeftCents(inMonthOf: first)
                if best == nil || left > best!.left { best = (m.monthKey, left) }
            }
        }
        out.bestMonth = best?.key

        guard let firstKey = planMonths.first, let lastKey = planMonths.last,
              let planStart = MonthKey.firstDay(of: firstKey, calendar: calendar),
              let lastMonthStart = MonthKey.firstDay(of: lastKey, calendar: calendar),
              let planEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: lastMonthStart) else { return out }
        var day = calendar.startOfDay(for: max(planStart, streakStart))
        let last = calendar.startOfDay(for: min(today, planEnd))
        while day <= last {
            out.daysCounted += 1
            if !summary(on: day).isOver { out.daysOnBudget += 1 }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return out
    }

    // MARK: - Category limits

    struct LimitStatus: Identifiable, Equatable {
        enum Level { case ok, near, over }
        var category: String
        var spentCents: Int
        var limitCents: Int
        var id: String { category }
        var leftCents: Int { limitCents - spentCents }
        /// 80% or more is "near"; more than the limit is "over".
        var level: Level {
            if spentCents > limitCents { return .over }
            return limitCents > 0 && spentCents * 5 >= limitCents * 4 ? .near : .ok
        }
    }

    func spent(category: String, inMonthOf date: Date) -> Int {
        let m = monthInterval(containing: date)
        return entries.lazy
            .filter { $0.category == category && $0.date >= m.start && $0.date < m.end }
            .reduce(0) { $0 + $1.cents }
    }

    /// Every category with a limit, the closest to (or furthest over) its limit first.
    func limitStatuses(limits: [String: Int], on date: Date) -> [LimitStatus] {
        limits.filter { $0.value > 0 }
            .map { LimitStatus(category: $0.key, spentCents: spent(category: $0.key, inMonthOf: date), limitCents: $0.value) }
            .sorted { Double($0.spentCents) / Double($0.limitCents) > Double($1.spentCents) / Double($1.limitCents) }
    }

    // MARK: - Weekly summary

    struct WeekSummary: Equatable {
        var spentCents = 0
        var daysOnBudget = 0
        var daysCounted = 0
        /// The category with the most everyday spending this week, if any.
        var topCategory: String?
    }

    /// Monday to Sunday of the week ending on `sunday`, counting only days up to `now` and not before `since`.
    func weekSummary(endingOn sunday: Date, now: Date, since: Date) -> WeekSummary {
        var out = WeekSummary()
        let end = calendar.startOfDay(for: sunday)
        guard let monday = calendar.date(byAdding: .day, value: -6, to: end) else { return out }
        var byCategory: [String: Int] = [:]
        var day = max(monday, calendar.startOfDay(for: since))
        let last = min(end, calendar.startOfDay(for: now))
        while day <= last {
            let s = summary(on: day)
            out.spentCents += s.spentCents
            out.daysCounted += 1
            if !s.isOver { out.daysOnBudget += 1 }
            let next = calendar.date(byAdding: .day, value: 1, to: day)!
            for e in entries where e.countsAsLiving && e.date >= day && e.date < next {
                byCategory[e.category, default: 0] += e.cents
            }
            day = next
        }
        out.topCategory = byCategory.filter { !$0.key.isEmpty && $0.value > 0 }
            .max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
        return out
    }

    /// True once every plan month has ended.
    static func planHasEnded(planMonths: [String], today: Date, calendar: Calendar = .current) -> Bool {
        guard let last = planMonths.last else { return false }
        return MonthKey.key(for: today, calendar: calendar) > last
    }
}
