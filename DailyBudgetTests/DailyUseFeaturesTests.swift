import XCTest
@testable import DailyBudget

/// Quick add, reminders and the widget snapshot.
final class DailyUseFeaturesTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Phnom_Penh")!
        return c
    }()
    private let months = ["2026-11", "2026-12", "2027-01", "2027-02", "2027-03", "2027-04"]

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func calc(_ entries: [BudgetCalculator.Entry] = []) -> BudgetCalculator {
        BudgetCalculator(entries: entries, livingMonthlyCents: 9_200, calendar: cal)
    }

    // MARK: Quick add

    func testQuickAddPutsMostFrequentFirstAndSkipsBills() {
        let now = at(2026, 11, 20)
        let past: [QuickAdd.Past] = [
            .init(category: .coffee, note: "Iced coffee", cents: 125, date: at(2026, 11, 18)),
            .init(category: .coffee, note: "iced coffee ", cents: 125, date: at(2026, 11, 19)),
            .init(category: .food, note: "Rice", cents: 150, date: at(2026, 11, 19)),
            .init(category: .transport, note: "", cents: 100, date: at(2026, 11, 17)),
            .init(category: .bills, note: "Bank", cents: 20_000, date: at(2026, 11, 19)),
            .init(category: .engagement, note: "Ring", cents: 50_000, date: at(2026, 11, 19)),
            .init(category: .food, note: "Old", cents: 300, date: at(2026, 8, 1)),  // too long ago
        ]
        let items = QuickAdd.suggestions(from: past, now: now, calendar: cal)
        XCTAssertEqual(items.map(\.title), ["Iced coffee", "Rice", "Transport"])
        XCTAssertEqual(items.first?.cents, 125)
    }

    func testQuickAddKeepsDifferentAmountsApart() {
        let now = at(2026, 11, 20)
        let past: [QuickAdd.Past] = [
            .init(category: .coffee, note: "Coffee", cents: 125, date: at(2026, 11, 18)),
            .init(category: .coffee, note: "Coffee", cents: 200, date: at(2026, 11, 19)),
        ]
        let items = QuickAdd.suggestions(from: past, now: now, calendar: cal)
        XCTAssertEqual(items.map(\.cents), [200, 125])  // same count, newest first
    }

    // MARK: Reminders

    private func plan(now: Date, _ s: ReminderPlanner.Settings, loggedToday: Bool = false,
                      bills: [ReminderPlanner.BillDue] = [], entries: [BudgetCalculator.Entry] = []) -> [ReminderPlanner.Reminder] {
        ReminderPlanner.plan(now: now, settings: s, calculator: calc(entries), loggedToday: loggedToday,
                             bills: bills, planMonths: months)
    }

    func testNothingIsScheduledWhenAllRemindersAreOff() {
        XCTAssertTrue(plan(now: at(2026, 11, 4), .init()).isEmpty)
    }

    func testOnlyTheNextMorningSaysTheExactLimit() {
        var s = ReminderPlanner.Settings(); s.morningOn = true
        // Nov 4, 9 PM, $5 spent so far: tomorrow (27 days left incl. the 5th) = $87 / 26 days.
        let entries: [BudgetCalculator.Entry] = [.init(date: at(2026, 11, 2), cents: 500, countsAsLiving: true)]
        let r = plan(now: at(2026, 11, 4, 21), s, entries: entries)
        XCTAssertEqual(r.count, 6)  // today's 8 AM already passed
        XCTAssertEqual(r[0].fireDate, at(2026, 11, 5, 8))
        XCTAssertEqual(r[0].body, "Today you can spend $3.34.")
        XCTAssertEqual(r[1].body, "Open Daily Budget to see today's limit.")
    }

    func testEveningIsSkippedTodayOnceSomethingIsLogged() {
        var s = ReminderPlanner.Settings(); s.eveningOn = true
        let now = at(2026, 11, 4, 10)
        let notLogged = plan(now: now, s)
        XCTAssertEqual(notLogged.first?.fireDate, at(2026, 11, 4, 20))
        XCTAssertEqual(notLogged.first?.body, "Nothing logged yet today. You still have $3.40 to spend.")
        let logged = plan(now: now, s, loggedToday: true)
        XCTAssertEqual(logged.first?.fireDate, at(2026, 11, 5, 20))
        XCTAssertEqual(logged.count, notLogged.count - 1)
    }

    func testBillRemindersListOnlyUnpaidBillsOnThe1stAnd25th() {
        var s = ReminderPlanner.Settings(); s.billsOn = true
        let bills: [ReminderPlanner.BillDue] = [
            .init(name: "Bank", cents: 20_000, month: "2026-11", isPaid: true),
            .init(name: "Wifi", cents: 1_800, month: "2026-11", isPaid: false),
            .init(name: "Bank", cents: 20_000, month: "2026-12", isPaid: false),
            .init(name: "Credit card", cents: 70_000, month: "2026-12", isPaid: false),
        ]
        let r = plan(now: at(2026, 11, 4), s, bills: bills)
        // November: the 1st has passed, so only the 25th. December: both.
        XCTAssertEqual(r.map(\.id), ["bills-unpaid-2026-11", "bills-due-2026-12", "bills-unpaid-2026-12"])
        XCTAssertEqual(r[0].fireDate, at(2026, 11, 25, 9))
        XCTAssertEqual(r[0].body, "November: Wifi $18. Tick them in Plan once paid.")
        XCTAssertEqual(r[1].title, "Bills due in December")
        XCTAssertEqual(r[1].body, "Bank $200, Credit card $700. Total $900.")
    }

    func testNoDailyRemindersAfterThePlanEnds() {
        var s = ReminderPlanner.Settings(); s.morningOn = true; s.eveningOn = true
        let r = plan(now: at(2027, 4, 28, 6), s)
        // Apr 28, 29, 30 only: 3 mornings + 3 evenings.
        XCTAssertEqual(r.count, 6)
        XCTAssertTrue(r.allSatisfy { cal.component(.month, from: $0.fireDate) == 4 })
    }

    // MARK: Widget snapshot

    func testWidgetSnapshotGivesTheSameNumbersAsTheApp() {
        let entries: [BudgetCalculator.Entry] = [
            .init(date: at(2026, 11, 2), cents: 500, countsAsLiving: true),
            .init(date: at(2026, 11, 4, 9), cents: 125, countsAsLiving: true),
        ]
        let snap = WidgetSnapshot(livingMonthlyCents: 9_200,
                                  items: entries.map { .init(date: $0.date, cents: $0.cents) }, updatedAt: .now)
        let widget = snap.calculator(calendar: cal).summary(on: at(2026, 11, 4, 18))
        let app = calc(entries).summary(on: at(2026, 11, 4, 18))
        XCTAssertEqual(widget.limitCents, app.limitCents)
        XCTAssertEqual(widget.spentCents, 125)
    }

    func testWidgetStartsFreshInANewMonthWithoutTheApp() {
        let snap = WidgetSnapshot(livingMonthlyCents: 9_200,
                                  items: [.init(date: at(2026, 11, 30), cents: 900)], updatedAt: .now)
        // December 1st: $92 over 31 days, November spending doesn't count.
        XCTAssertEqual(snap.calculator(calendar: cal).summary(on: at(2026, 12, 1, 8)).limitCents, 296)
    }

    func testWidgetSnapshotSurvivesSaveAndLoad() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.widget.snapshot"))
        defer { defaults.removePersistentDomain(forName: "test.widget.snapshot") }
        let snap = WidgetSnapshot(livingMonthlyCents: 9_200, items: [.init(date: at(2026, 11, 4), cents: 125)],
                                  updatedAt: at(2026, 11, 4))
        snap.save(to: defaults)
        XCTAssertEqual(WidgetSnapshot.load(from: defaults), snap)
    }
}
