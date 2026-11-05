import XCTest
import SwiftData
@testable import DailyBudget

final class SubscriptionTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Phnom_Penh")!
        return c
    }()

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testMonthlyRenewalKeepsTheAnchorDayInShortMonths() {
        let jan31 = at(2027, 1, 31)
        let feb = SubscriptionSchedule.next(after: jan31, cycle: .monthly, anchorDay: 31, calendar: cal)
        let mar = SubscriptionSchedule.next(after: feb, cycle: .monthly, anchorDay: 31, calendar: cal)
        XCTAssertEqual(feb, at(2027, 2, 28))
        XCTAssertEqual(mar, at(2027, 3, 31))
        XCTAssertEqual(SubscriptionSchedule.next(after: at(2026, 11, 5), cycle: .yearly, anchorDay: 5, calendar: cal), at(2027, 11, 5))
    }

    func testEveryMissedRenewalIsPaidOnceAndTheNextOneIsInTheFuture() {
        let due = SubscriptionSchedule.due(nextRenewal: at(2026, 11, 3), cycle: .monthly, anchorDay: 3,
                                           now: at(2027, 1, 10), calendar: cal)
        XCTAssertEqual(due.dates, [at(2026, 11, 3), at(2026, 12, 3), at(2027, 1, 3)])
        XCTAssertEqual(due.next, at(2027, 2, 3))
        XCTAssertTrue(SubscriptionSchedule.due(nextRenewal: at(2026, 11, 20), cycle: .monthly, anchorDay: 20,
                                               now: at(2026, 11, 5), calendar: cal).dates.isEmpty)
    }

    func testPlannedMonthsAndMonthlyCost() {
        let plan = ["2026-11", "2026-12", "2027-01", "2027-02"]
        XCTAssertEqual(SubscriptionSchedule.dueMonths(in: plan, cycle: .monthly, startMonth: "2026-12", renewalMonth: 12,
                                                      isActive: true, currentMonth: "2026-11"), ["2026-12", "2027-01", "2027-02"])
        XCTAssertEqual(SubscriptionSchedule.dueMonths(in: plan, cycle: .yearly, startMonth: "2026-11", renewalMonth: 1,
                                                      isActive: true, currentMonth: "2026-11"), ["2027-01"])
        // Stopped in December: only months already past still count.
        XCTAssertEqual(SubscriptionSchedule.dueMonths(in: plan, cycle: .monthly, startMonth: "2026-11", renewalMonth: 11,
                                                      isActive: false, currentMonth: "2026-12"), ["2026-11"])
        XCTAssertEqual(SubscriptionSchedule.monthlyCents(amountCents: 9_999, cycle: .yearly), 833)
        XCTAssertEqual(SubscriptionSchedule.symbol(for: "Netflix Premium"), "tv.fill")
        XCTAssertEqual(SubscriptionSchedule.symbol(for: "Something"), "repeat.circle.fill")
    }

    func testRenewalReminderTwoDaysBefore() {
        var s = ReminderPlanner.Settings(); s.subscriptionsOn = true
        let id = UUID()
        let calc = BudgetCalculator(entries: [], livingMonthlyCents: 9_200, calendar: cal)
        let r = ReminderPlanner.plan(now: at(2026, 11, 5, 12), settings: s, calculator: calc, loggedToday: false,
                                     bills: [], planMonths: ["2026-11"],
                                     renewals: [.init(id: id, name: "Spotify", cents: 599, date: at(2026, 11, 20)),
                                                .init(id: UUID(), name: "Too far", cents: 100, date: at(2027, 3, 1))])
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].fireDate, at(2026, 11, 18))
        XCTAssertEqual(r[0].title, "Spotify renews soon")
    }

    @MainActor
    func testRenewalsAreAddedAsBillsExpensesThatDontTouchDailyMoney() throws {
        let container = try ModelContainer(for: Expense.self, Bill.self, BudgetSettings.self, Income.self,
                                           RecurringExpense.self, Subscription.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let now = Date.now
        let sub = Subscription(name: "iCloud", amountCents: 99, cycle: .monthly, nextRenewal: now.addingTimeInterval(-3600))
        context.insert(sub)
        XCTAssertEqual(SubscriptionRunner.addDue(in: context, now: now), 1)
        XCTAssertEqual(SubscriptionRunner.addDue(in: context, now: now), 0)
        let e = try XCTUnwrap(try context.fetch(FetchDescriptor<Expense>()).first)
        XCTAssertEqual(e.category, .bills)
        XCTAssertFalse(e.category.countsAsLiving)
        XCTAssertGreaterThan(sub.nextRenewal, now)
    }
}
