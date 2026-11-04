import XCTest
import SwiftData
@testable import DailyBudget

@MainActor
final class BillPaymentsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        container = try ModelContainer(for: Expense.self, Bill.self, BudgetSettings.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    override func tearDown() {
        container = nil
    }

    private func makeBank() -> Bill {
        let bill = Bill(name: "Bank", amountCents: 20_000, dueMonths: ["2026-11", "2026-12"], sortOrder: 0)
        context.insert(bill)
        return bill
    }

    private func expenses() throws -> [Expense] { try context.fetch(FetchDescriptor<Expense>()) }

    func testTickingPaidAddsOneBillsExpenseAndUntickingRemovesIt() throws {
        let bank = makeBank()
        BillPayments.setPaid(true, bill: bank, month: "2026-11", in: context)
        BillPayments.setPaid(true, bill: bank, month: "2026-11", in: context)  // no duplicate

        var list = try expenses()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].amountCents, 20_000)
        XCTAssertEqual(list[0].category, .bills)
        XCTAssertEqual(list[0].note, "Bank")
        XCTAssertTrue(bank.isPaid(in: "2026-11"))

        BillPayments.toggle(bill: bank, month: "2026-11", in: context)
        list = try expenses()
        XCTAssertTrue(list.isEmpty)
        XCTAssertFalse(bank.isPaid(in: "2026-11"))
    }

    func testDeletingThePaymentExpenseUnticksTheBill() throws {
        let bank = makeBank()
        BillPayments.setPaid(true, bill: bank, month: "2026-11", in: context)
        let payment = try XCTUnwrap(try expenses().first)

        BillPayments.delete(payment, in: context)
        XCTAssertTrue(try expenses().isEmpty)
        XCTAssertFalse(bank.isPaid(in: "2026-11"))
    }

    func testDeletingANormalExpenseLeavesBillsAlone() throws {
        let bank = makeBank()
        BillPayments.setPaid(true, bill: bank, month: "2026-11", in: context)
        let coffee = Expense(amountCents: 125, category: .coffee)
        context.insert(coffee)

        BillPayments.delete(coffee, in: context)
        XCTAssertEqual(try expenses().count, 1)
        XCTAssertTrue(bank.isPaid(in: "2026-11"))
    }

    func testSyncAddsMissingPaymentsOnceForBillsTickedEarlier() throws {
        let bank = makeBank()
        bank.paidMonths = ["2026-11"]  // ticked before payments created expenses

        BillPayments.sync(in: context)
        BillPayments.sync(in: context)
        let list = try expenses()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].billMonth, "2026-11")
    }

    func testPaidBillsCountInMonthlySpending() throws {
        let bank = makeBank()
        let november = try XCTUnwrap(MonthKey.firstDay(of: "2026-11"))
        BillPayments.setPaid(true, bill: bank, month: "2026-11", in: context,
                             now: november.addingTimeInterval(3 * 86_400))
        let months = BudgetCalculator(expenses: try expenses(), settings: nil)
            .monthlySpending(months: ["2026-11", "2026-12"])
        XCTAssertEqual(months[0].billsCents, 20_000)
        XCTAssertEqual(months[0].livingCents, 0)  // bills never touch daily living money
        XCTAssertEqual(months[1].totalCents, 0)
    }
}
