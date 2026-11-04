import XCTest
@testable import DailyBudget

/// Category limits, weekly summary, app expiry, search, and the widget/Siri quick-add queue.
final class DailyHabitsTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Phnom_Penh")!
        return c
    }()
    private let plan = ["2026-11", "2026-12", "2027-01", "2027-02", "2027-03", "2027-04"]

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func calc(_ entries: [BudgetCalculator.Entry]) -> BudgetCalculator {
        BudgetCalculator(entries: entries, livingMonthlyCents: 9_200, calendar: cal)
    }

    private func spend(_ cents: Int, _ category: String, _ date: Date) -> BudgetCalculator.Entry {
        .init(date: date, cents: cents, countsAsLiving: category != "bills", category: category)
    }

    // MARK: Category limits

    func testLimitsWarnAt80PercentAndWhenOver() {
        let c = calc([
            spend(1_250, "coffee", at(2026, 11, 2)),   // 83% of $15
            spend(3_500, "food", at(2026, 11, 3)),     // over $30
            spend(500, "transport", at(2026, 11, 3)),  // 25% of $20
            spend(9_999, "coffee", at(2026, 10, 30)),  // last month: ignored
        ])
        let s = c.limitStatuses(limits: ["coffee": 1_500, "food": 3_000, "transport": 2_000, "fun": 0], on: at(2026, 11, 20))
        XCTAssertEqual(s.map(\.category), ["food", "coffee", "transport"])  // most used first; 0 = no limit
        XCTAssertEqual(s.map(\.level), [.over, .near, .ok])
        XCTAssertEqual(s[0].leftCents, -500)
    }

    // MARK: Weekly summary

    func testWeekSummaryCountsMondayToSundayUpToNow() {
        // Week of Mon Nov 16 – Sun Nov 22, 2026.
        let c = calc([
            spend(200, "coffee", at(2026, 11, 16)),
            spend(1_000, "food", at(2026, 11, 17)),       // over that day's limit
            spend(300, "coffee", at(2026, 11, 18)),
            spend(20_000, "bills", at(2026, 11, 18)),     // not everyday money
            spend(500, "fun", at(2026, 11, 15)),          // Sunday before: other week
        ])
        let w = c.weekSummary(endingOn: at(2026, 11, 22), now: at(2026, 11, 19, 20), since: at(2026, 11, 1))
        XCTAssertEqual(w.daysCounted, 4)       // Mon–Thu so far
        XCTAssertEqual(w.daysOnBudget, 3)
        XCTAssertEqual(w.spentCents, 1_500)
        XCTAssertEqual(w.topCategory, "food")
    }

    func testWeeklyReminderIsOnSundayEvening() {
        var s = ReminderPlanner.Settings(); s.weeklyOn = true
        let r = ReminderPlanner.plan(now: at(2026, 11, 19, 10), settings: s, calculator: calc([spend(500, "coffee", at(2026, 11, 18))]),
                                     loggedToday: false, bills: [], planMonths: plan, streakStart: at(2026, 11, 1),
                                     categoryTitle: { $0 == "coffee" ? "Coffee" : $0 })
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].fireDate, at(2026, 11, 22, 19))
        XCTAssertEqual(r[0].body, "$5.00 spent on everyday things. 4 of 4 days on budget. Most went to Coffee.")
    }

    // MARK: App expiry

    func testExpiryIsReadFromTheProfileAndRemindedTheDayBefore() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>ExpirationDate</key><date>2026-11-11T08:30:00Z</date></dict></plist>
        """
        // The real file wraps the plist in signature bytes.
        let data = Data([0x30, 0x82, 0x01]) + Data(plist.utf8) + Data([0x00, 0xA0])
        let expiry = try XCTUnwrap(AppExpiry.expirationDate(fromProvision: data))
        XCTAssertEqual(expiry, ISO8601DateFormatter().date(from: "2026-11-11T08:30:00Z"))
        XCTAssertEqual(AppExpiry.daysLeft(until: expiry, now: expiry.addingTimeInterval(-86_400 * 2.5)), 2)
        XCTAssertNil(AppExpiry.expirationDate(fromProvision: Data("nothing here".utf8)))

        var s = ReminderPlanner.Settings(); s.expiryOn = true
        let r = ReminderPlanner.plan(now: at(2026, 11, 5), settings: s, calculator: calc([]), loggedToday: false,
                                     bills: [], planMonths: plan, appExpiresAt: expiry)
        // 08:30 UTC = 15:30 in Phnom Penh on the 11th: 9 AM on the 10th, and 9 AM on the 11th.
        XCTAssertEqual(r.map(\.id), ["expiry-before", "expiry-today"])
        XCTAssertEqual(r[0].fireDate, at(2026, 11, 10, 9))
    }

    // MARK: Search

    func testSearchMatchesNotesCategoriesAndExactAmounts() {
        XCTAssertTrue(ExpenseSearch.matches(note: "Iced Latte", category: "Coffee", cents: 125, query: "latte", queryCents: nil))
        XCTAssertTrue(ExpenseSearch.matches(note: "", category: "Coffee", cents: 125, query: "cof", queryCents: nil))
        XCTAssertTrue(ExpenseSearch.matches(note: "", category: "Food", cents: 125, query: "1.25", queryCents: 125))
        XCTAssertFalse(ExpenseSearch.matches(note: "Rice", category: "Food", cents: 150, query: "1.25", queryCents: 125))
        XCTAssertTrue(ExpenseSearch.matches(note: "Café", category: "Food", cents: 150, query: "cafe", queryCents: nil))
    }

    // MARK: Quick-add queue

    func testQueueKeepsEachTapOnceUntilTheAppTakesThem() throws {
        let store = try XCTUnwrap(UserDefaults(suiteName: "test.quickadd.queue"))
        defer { store.removePersistentDomain(forName: "test.quickadd.queue") }
        let a = PendingExpense(id: UUID(), cents: 125, category: "coffee", note: "Coffee", date: at(2026, 11, 4))
        QuickAddQueue.append(a, to: store)
        QuickAddQueue.append(a, to: store)  // same tap delivered twice
        QuickAddQueue.append(PendingExpense(id: UUID(), cents: 85, category: "food", note: "Coconut", date: at(2026, 11, 4)), to: store)
        XCTAssertEqual(QuickAddQueue.takeAll(from: store).map(\.cents), [125, 85])
        XCTAssertTrue(QuickAddQueue.takeAll(from: store).isEmpty)
        XCTAssertFalse(QuickAddQueue.countsAsLiving("bills"))
        XCTAssertTrue(QuickAddQueue.countsAsLiving("coffee"))
    }
}
