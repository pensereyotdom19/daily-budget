import XCTest
import SwiftData
@testable import DailyBudget

/// Extra income, savings, "can I afford it", plan summary, new plans, recurring expenses and riel.
final class MoreFeaturesTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Phnom_Penh")!
        return c
    }()
    private let plan = ["2026-11", "2026-12", "2027-01", "2027-02", "2027-03", "2027-04"]

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func calc(_ entries: [BudgetCalculator.Entry] = [], extra: [String: Int] = [:]) -> BudgetCalculator {
        BudgetCalculator(entries: entries, livingMonthlyCents: 9_200, calendar: cal, extraLivingByMonth: extra)
    }

    // MARK: Extra income

    func testIncomeForLivingRaisesTheLimitOnlyInItsMonth() {
        let c = calc(extra: ["2026-11": 2_700])
        // ($92 + $27) / 30 days = $3.96
        XCTAssertEqual(c.limitCents(on: at(2026, 11, 1)), 396)
        XCTAssertEqual(c.monthLeftCents(inMonthOf: at(2026, 11, 1)), 11_900)
        XCTAssertEqual(c.limitCents(on: at(2026, 12, 1)), 296)  // December unchanged
    }

    func testSavingsAddUpLeftoversIncomeAndEarlierPlans() {
        let c = calc([.init(date: at(2026, 11, 3), cents: 8_000, countsAsLiving: true)])
        let months = c.savingsByMonth(planMonths: plan, today: at(2027, 1, 10),
                                      savingsIncomeByMonth: ["2026-12": 5_000, "2026-10": 999])
        XCTAssertEqual(months.map(\.monthKey), ["2026-11", "2026-12", "2027-01"])  // October is before the plan
        XCTAssertEqual(months.map(\.leftoverCents), [1_200, 9_200, 0])            // January hasn't ended
        XCTAssertEqual(months[1].incomeCents, 5_000)
        XCTAssertEqual(c.emergencySavingsCents(planMonths: plan, today: at(2027, 1, 10),
                                               savingsIncomeByMonth: ["2026-12": 5_000], savedBeforeCents: 300),
                       300 + 1_200 + 9_200 + 5_000)
    }

    // MARK: Can I afford it?

    func testWhatIfShowsTodayTomorrowAndTheMonth() {
        let w = calc().whatIf(spending: 500, on: at(2026, 11, 4))
        // Nov 4: limit $3.40. After $5: -$1.60 today; tomorrow ($92 - $5) / 26 = $3.34 instead of $3.53.
        XCTAssertEqual(w.leftTodayAfter, -160)
        XCTAssertFalse(w.fitsToday)
        XCTAssertEqual(w.tomorrowLimitNow, 353)
        XCTAssertEqual(w.tomorrowLimitAfter, 334)
        XCTAssertEqual(w.monthLeftAfter, 8_700)
        XCTAssertTrue(w.tomorrowInSameMonth)
    }

    func testWhatIfOnTheLastDayLeavesNextMonthAlone() {
        let w = calc().whatIf(spending: 100, on: at(2026, 11, 30))
        XCTAssertFalse(w.tomorrowInSameMonth)
        XCTAssertEqual(w.tomorrowLimitAfter, w.tomorrowLimitNow)
    }

    // MARK: Plan summary

    func testPlanSummaryCountsDaysOnBudgetAndTheBestMonth() {
        let c = calc([
            .init(date: at(2026, 11, 2), cents: 1_000, countsAsLiving: true),   // over that day
            .init(date: at(2026, 12, 5), cents: 5_000, countsAsLiving: true),
            .init(date: at(2026, 11, 3), cents: 20_000, countsAsLiving: false),
        ])
        let s = c.planSummary(planMonths: plan, today: at(2027, 1, 1), streakStart: at(2026, 11, 1))
        XCTAssertEqual(s.daysCounted, 30 + 31 + 1)
        XCTAssertEqual(s.daysOnBudget, s.daysCounted - 2)  // Nov 2 and Dec 5
        XCTAssertEqual(s.livingSpentCents, 6_000)
        XCTAssertEqual(s.billsCents, 20_000)
        XCTAssertEqual(s.livingPlannedCents, 9_200 * 3)
        XCTAssertEqual(s.bestMonth, "2026-11")  // $82 left vs $42
        XCTAssertFalse(BudgetCalculator.planHasEnded(planMonths: plan, today: at(2027, 4, 30)))
        XCTAssertTrue(BudgetCalculator.planHasEnded(planMonths: plan, today: at(2027, 5, 1)))
    }

    // MARK: New plan

    func testNewPlanCarriesMonthlyAndEvery3MonthBillsButNotOneOffs() {
        XCTAssertEqual(BillFrequency.guess(dueMonths: plan, planMonths: plan), .monthly)
        XCTAssertEqual(BillFrequency.guess(dueMonths: ["2026-11", "2027-02"], planMonths: plan), .every3Months)
        XCTAssertNil(BillFrequency.guess(dueMonths: ["2026-12"], planMonths: plan))
        let next = MonthKey.range(start: "2027-05", count: 6)
        XCTAssertEqual(BillFrequency.every3Months.dueMonths(in: next), ["2027-05", "2027-08"])
        XCTAssertEqual(BillFrequency.once.dueMonths(in: next, onceIndex: 2), ["2027-07"])
    }

    func testNewPlanStartsAfterTheCurrentOneOrThisMonth() {
        XCTAssertEqual(PlanMath.suggestedStart(currentPlanMonths: plan, today: at(2027, 4, 10), calendar: cal), "2027-05")
        XCTAssertEqual(PlanMath.suggestedStart(currentPlanMonths: plan, today: at(2027, 7, 2), calendar: cal), "2027-07")
        XCTAssertEqual(PlanMath.plannedTotal(livingMonthlyCents: 9_200, monthCount: 6, engagementCents: 150_000,
                                             bills: [(cents: 20_000, dueCount: 6), (cents: 500, dueCount: 2)]),
                       55_200 + 150_000 + 120_000 + 1_000)
    }

    @MainActor
    func testHistoryKeepsEarlierPlanMonths() throws {
        let s = BudgetSettings()
        s.historyStartMonth = "2026-11"
        s.startMonth = "2027-05"
        s.monthCount = 3
        XCTAssertEqual(s.historyMonths.first, "2026-11")
        XCTAssertEqual(s.historyMonths.last, "2027-07")
        XCTAssertEqual(s.historyMonths.count, 9)
    }

    // MARK: Recurring

    func testRecurringIsAddedOncePerMonthOnItsDay() {
        let due = RecurringSchedule.due(dayOfMonth: 31, startMonth: "2026-11", lastAddedMonth: nil,
                                        now: at(2027, 2, 28, 10), calendar: cal)
        XCTAssertEqual(due.map(\.month), ["2026-11", "2026-12", "2027-01", "2027-02"])
        XCTAssertEqual(cal.component(.day, from: due[0].date), 30)  // November has 30 days
        XCTAssertEqual(cal.component(.day, from: due[3].date), 28)  // February
        let later = RecurringSchedule.due(dayOfMonth: 5, startMonth: "2026-11", lastAddedMonth: "2026-12",
                                          now: at(2027, 1, 4), calendar: cal)
        XCTAssertTrue(later.isEmpty)  // January 5th hasn't come yet
    }

    // MARK: Riel

    func testRielConvertsToCentsAtTheRate() {
        XCTAssertEqual(Money.rielToCents(5_000, rate: 4_100), 122)
        XCTAssertEqual(Money.rielToCents(4_100, rate: 4_100), 100)
        XCTAssertEqual(Money.parseRiel("5,000"), 5_000)
        XCTAssertEqual(Money.parseRiel("៥០០០"), 5_000)  // Khmer digits
        XCTAssertNil(Money.parseRiel("abc"))
        XCTAssertNil(Money.parseRiel("0"))
        XCTAssertEqual(Money.formatRiel(12_500), "៛12,500")
    }

    // MARK: Widget

    func testWidgetIncludesExtraLivingMoney() {
        let snap = WidgetSnapshot(livingMonthlyCents: 9_200, items: [], updatedAt: .now, extraLivingByMonth: ["2026-11": 2_700])
        XCTAssertEqual(snap.calculator(calendar: cal).limitCents(on: at(2026, 11, 1)), 396)
    }
}
