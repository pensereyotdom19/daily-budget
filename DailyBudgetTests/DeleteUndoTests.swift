import XCTest
import SwiftData
@testable import DailyBudget

@MainActor
final class DeleteUndoTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try ModelContainer(for: Expense.self, Bill.self, BudgetSettings.self, Income.self, RecurringExpense.self, Subscription.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func allExpenses() -> [Expense] { (try? context.fetch(FetchDescriptor<Expense>())) ?? [] }

    func testUndoPutsTheExpenseBackWithANewID() {
        let date = Date(timeIntervalSince1970: 1_793_000_000)
        let e = Expense(amountCents: 125, category: .coffee, note: "Iced coffee", date: date)
        context.insert(e); try? context.save()
        let oldID = e.id
        let undo = DeleteUndo()
        undo.delete(e, in: context)
        XCTAssertTrue(allExpenses().isEmpty)
        XCTAssertEqual(undo.last?.title, "Iced coffee")

        undo.undo(in: context)
        XCTAssertNil(undo.last)
        let back = allExpenses()
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back[0].amountCents, 125)
        XCTAssertEqual(back[0].category, .coffee)
        XCTAssertEqual(back[0].date, date)
        // New id: sync uploads it as a new expense even if the delete already reached the server.
        XCTAssertNotEqual(back[0].id, oldID)
    }

    func testUndoingABillPaymentTicksTheBillAgain() {
        let bill = Bill(name: "Bank", amountCents: 20_000, dueMonths: ["2026-11"], sortOrder: 0)
        context.insert(bill); try? context.save()
        BillPayments.toggle(bill: bill, month: "2026-11", in: context)
        let payment = try! XCTUnwrap(allExpenses().first)
        let undo = DeleteUndo()
        undo.delete(payment, in: context)
        XCTAssertFalse(bill.paidMonths.contains("2026-11"))

        undo.undo(in: context)
        XCTAssertTrue(bill.paidMonths.contains("2026-11"))
        XCTAssertEqual(allExpenses().count, 1)
        XCTAssertEqual(allExpenses().first?.billID, bill.id)
    }

    func testUndoWithNothingDeletedDoesNothing() {
        DeleteUndo().undo(in: context)
        XCTAssertTrue(allExpenses().isEmpty)
    }
}
