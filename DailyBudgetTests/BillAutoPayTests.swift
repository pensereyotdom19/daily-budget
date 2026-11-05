import XCTest
import SwiftData
@testable import DailyBudget

@MainActor
final class BillAutoPayTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let cal = Calendar.current

    override func setUpWithError() throws {
        container = try ModelContainer(for: Expense.self, Bill.self, BudgetSettings.self, Income.self,
                                       RecurringExpense.self, Subscription.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func electricity() -> Bill {
        let b = Bill(name: "Electricity", amountCents: 10_000, dueMonths: ["2026-11", "2026-12", "2027-01"], sortOrder: 1)
        context.insert(b)
        return b
    }

    private func payments() throws -> [Expense] {
        try context.fetch(FetchDescriptor<Expense>()).filter { $0.note == "Electricity" }.sorted { $0.date < $1.date }
    }

    func testBillIsPaidOnItsDayWithThatDate() throws {
        let bill = electricity()
        BillAutoPay.setDueDay(15, for: bill, in: context, now: at(2026, 11, 5))
        XCTAssertFalse(bill.isPaid(in: "2026-11"))          // the 15th hasn't come yet
        XCTAssertEqual(BillAutoPay.run(in: context, now: at(2026, 11, 15, 10)), 1)
        XCTAssertTrue(bill.isPaid(in: "2026-11"))
        XCTAssertEqual(try payments().first?.date, at(2026, 11, 15, 9))
        XCTAssertEqual(try payments().first?.category, .bills)
        XCTAssertEqual(BillAutoPay.run(in: context, now: at(2026, 11, 20)), 0)  // only once
    }

    func testUntickingByHandSticksAndNextMonthStillPays() throws {
        let bill = electricity()
        BillAutoPay.setDueDay(1, for: bill, in: context, now: at(2026, 11, 5))  // Nov 1 already passed: paid now
        XCTAssertTrue(bill.isPaid(in: "2026-11"))
        BillPayments.setPaid(false, bill: bill, month: "2026-11", in: context)
        BillAutoPay.run(in: context, now: at(2026, 11, 6))
        XCTAssertFalse(bill.isPaid(in: "2026-11"))          // stays unticked
        BillAutoPay.run(in: context, now: at(2026, 12, 2))
        XCTAssertTrue(bill.isPaid(in: "2026-12"))
        XCTAssertEqual(try payments().count, 1)
    }

    func testMissedDaysAreCaughtUpAndDay31UsesTheLastDay() throws {
        let bill = electricity()
        BillAutoPay.setDueDay(31, for: bill, in: context, now: at(2026, 11, 5))
        XCTAssertEqual(BillAutoPay.run(in: context, now: at(2027, 1, 31, 10)), 3)  // app not opened for months
        XCTAssertEqual(try payments().map { cal.component(.day, from: $0.date) }, [30, 31, 31])
        XCTAssertEqual(BillSchedule.dueDate(month: "2027-02", day: 31), at(2027, 2, 28, 9))
    }

    func testBillsWithoutADueDayAreLeftToYou() {
        let bill = electricity()
        XCTAssertEqual(BillAutoPay.run(in: context, now: at(2027, 2, 1)), 0)
        XCTAssertTrue(bill.paidMonths.isEmpty)
    }

    func testReminderTheDayBeforeInsteadOfThe1stAnd25th() {
        var s = ReminderPlanner.Settings(); s.billsOn = true
        let calc = BudgetCalculator(entries: [], livingMonthlyCents: 9_200)
        let r = ReminderPlanner.plan(now: at(2026, 11, 5), settings: s, calculator: calc, loggedToday: false,
                                     bills: [.init(name: "Electricity", cents: 10_000, month: "2026-11", isPaid: false, dueDay: 15),
                                             .init(name: "Water", cents: 500, month: "2026-11", isPaid: false)],
                                     planMonths: ["2026-11"])
        XCTAssertEqual(r.map(\.title), ["Electricity is due tomorrow", "Bills not paid yet"])
        XCTAssertEqual(r[0].fireDate, at(2026, 11, 14, 9))
        XCTAssertEqual(r[1].body, "November: Water $5. Tick them in Plan once paid.")
    }
}
