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

    func testStreakCountsOnlyFromFirstUse() {
        let start = BudgetCalculator.streakStart(planStart: day(2026, 11, 1, 0), firstOpened: day(2026, 11, 4, 15))
        XCTAssertEqual(calc([]).streak(endingOn: day(2026, 11, 4), since: start), 1)
        XCTAssertEqual(calc([]).streak(endingOn: day(2026, 11, 6), since: start), 3)
        // Opened before the plan starts: the plan start wins.
        XCTAssertEqual(BudgetCalculator.streakStart(planStart: day(2026, 11, 1, 0), firstOpened: day(2026, 10, 20)),
                       day(2026, 11, 1, 0))
        XCTAssertEqual(BudgetCalculator.streakStart(planStart: day(2026, 11, 1, 0), firstOpened: nil), day(2026, 11, 1, 0))
    }

    func testLeftoverOfFinishedMonthGoesToSavings() {
        let c = calc([.init(date: day(2026, 11, 10), cents: 1_000, countsAsLiving: true)])
        let months = MonthKey.range(start: "2026-11", count: 6)
        XCTAssertEqual(c.emergencySavingsCents(planMonths: months, today: day(2026, 11, 20)), 0)
        XCTAssertEqual(c.emergencySavingsCents(planMonths: months, today: day(2026, 12, 5)), 8_200)
    }

    func testMonthlySpendingSplitsGroupsPerMonth() {
        let c = calc([
            .init(date: day(2026, 11, 3), cents: 300, countsAsLiving: true),
            .init(date: day(2026, 11, 5), cents: 20_000, countsAsLiving: false),                       // bill
            .init(date: day(2026, 11, 6), cents: 150_000, countsAsLiving: false, isEngagement: true),  // engagement
            .init(date: day(2026, 12, 1), cents: 450, countsAsLiving: true),
            .init(date: day(2026, 10, 31), cents: 999, countsAsLiving: true),                          // before plan
        ])
        let m = c.monthlySpending(months: ["2026-11", "2026-12", "2027-01"])
        XCTAssertEqual(m.map(\.monthKey), ["2026-11", "2026-12", "2027-01"])
        XCTAssertEqual(m[0].livingCents, 300)
        XCTAssertEqual(m[0].billsCents, 20_000)
        XCTAssertEqual(m[0].engagementCents, 150_000)
        XCTAssertEqual(m[0].totalCents, 170_300)
        XCTAssertEqual(m[1].totalCents, 450)
        XCTAssertEqual(m[2].totalCents, 0)
    }

    func testPlannedPerMonthIsLivingPlusBillsDue() {
        let bills: [(cents: Int, dueMonths: [String])] = [
            (20_000, ["2026-11", "2026-12"]),  // Bank, monthly
            (70_000, ["2026-12"]),             // Credit card, December only
        ]
        XCTAssertEqual(BudgetCalculator.plannedCents(month: "2026-11", livingMonthlyCents: 9_200, bills: bills), 29_200)
        XCTAssertEqual(BudgetCalculator.plannedCents(month: "2026-12", livingMonthlyCents: 9_200, bills: bills), 99_200)
    }

    func testBillPaymentDateLandsInTheBillsMonth() {
        let now = day(2026, 11, 4, 15)
        // Ticked in its own month: dated now.
        XCTAssertEqual(BudgetCalculator.billPaymentDate(month: "2026-11", now: now, calendar: cal), now)
        // Ticked for another month: noon on the 1st of that month.
        XCTAssertEqual(BudgetCalculator.billPaymentDate(month: "2026-12", now: now, calendar: cal), day(2026, 12, 1, 12))
    }

    func testBillSymbolsMatchSeededBillNames() {
        XCTAssertEqual(Category.billSymbol(for: "Electricity"), "bolt.fill")
        XCTAssertEqual(Category.billSymbol(for: "Wifi"), "wifi")
        XCTAssertEqual(Category.billSymbol(for: "Water"), "drop.fill")
        XCTAssertEqual(Category.billSymbol(for: "Bank"), "building.columns.fill")
        XCTAssertEqual(Category.billSymbol(for: "Waste management"), "trash.fill")
        XCTAssertEqual(Category.billSymbol(for: "Credit card"), "creditcard.fill")
        XCTAssertNil(Category.billSymbol(for: "Something else"))
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
