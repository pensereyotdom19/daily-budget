import XCTest
@testable import DailyBudget

final class BudgetCalculatorTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Phnom_Penh")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func calc(_ entries: [BudgetCalculator.Entry]) -> BudgetCalculator {
        BudgetCalculator(entries: entries, livingMonthlyCents: 9_200, calendar: cal)
    }

    func testFirstDayLimitSplitsMonthEvenly() {
        // $92 over 30 days in November = $3.06 per day (rounded down).
        XCTAssertEqual(calc([]).limitCents(on: day(2026, 11, 1)), 306)
    }

    func testUnspentMoneyRollsForwardAndOverspendingLowersLimit() {
        let c = calc([.init(date: day(2026, 11, 1), cents: 500, countsAsLiving: true)])
        // $92 - $5 = $87 over 29 days = $3.00
        XCTAssertEqual(c.limitCents(on: day(2026, 11, 2)), 300)
        XCTAssertTrue(c.summary(on: day(2026, 11, 1)).isOver)
    }

    func testBillsAndEngagementDoNotCountAsLiving() {
        let c = calc([.init(date: day(2026, 11, 3), cents: 20_000, countsAsLiving: false)])
        XCTAssertEqual(c.spentCents(on: day(2026, 11, 3)), 0)
        XCTAssertEqual(c.monthLeftCents(inMonthOf: day(2026, 11, 3)), 9_200)
    }

    func testDaySummariesAreNewestFirstUpToDate() {
        let list = calc([]).daySummaries(inMonthOf: day(2026, 11, 4))
        XCTAssertEqual(list.count, 4)
        XCTAssertEqual(cal.component(.day, from: list.first!.day), 4)
    }

    func testStreakStopsAtOverDay() {
        let c = calc([
            .init(date: day(2026, 11, 2), cents: 400, countsAsLiving: true),  // over
            .init(date: day(2026, 11, 3), cents: 100, countsAsLiving: true),
            .init(date: day(2026, 11, 4), cents: 100, countsAsLiving: true),
        ])
        XCTAssertEqual(c.streak(endingOn: day(2026, 11, 4), since: day(2026, 11, 1, 0)), 2)
    }

    func testLeftoverOfFinishedMonthGoesToSavings() {
        let c = calc([.init(date: day(2026, 11, 10), cents: 1_000, countsAsLiving: true)])
        let months = MonthKey.range(start: "2026-11", count: 6)
        XCTAssertEqual(c.emergencySavingsCents(planMonths: months, today: day(2026, 11, 20)), 0)
        XCTAssertEqual(c.emergencySavingsCents(planMonths: months, today: day(2026, 12, 5)), 8_200)
    }

    func testMonthRangeCrossesYear() {
        XCTAssertEqual(MonthKey.range(start: "2026-11", count: 6),
                       ["2026-11", "2026-12", "2027-01", "2027-02", "2027-03", "2027-04"])
    }

    func testMoneyParseAndFormat() {
        XCTAssertEqual(Money.parse("1.25"), 125)
        XCTAssertEqual(Money.parse("0,75"), 75)
        XCTAssertNil(Money.parse(""))
        XCTAssertEqual(Money.format(470_000), "$4,700")
        XCTAssertEqual(Money.format(132), "$1.32")
    }
}
