import Foundation
import SwiftData

/// Keeps a bill's "paid" tick and its Bills expense in step, so paid bills show up in
/// History, monthly totals and CSV export without being entered twice.
///
/// - Ticking a bill paid adds one Bills expense (note = bill name) linked to that bill and month.
/// - Unticking it removes that expense.
/// - Deleting that expense unticks the bill.
enum BillPayments {
    static func toggle(bill: Bill, month: String, in context: ModelContext, now: Date = .now) {
        setPaid(!bill.isPaid(in: month), bill: bill, month: month, in: context, now: now)
    }

    static func setPaid(_ paid: Bool, bill: Bill, month: String, in context: ModelContext, now: Date = .now) {
        if paid {
            if !bill.paidMonths.contains(month) { bill.paidMonths.append(month) }
            if linkedExpenses(bill: bill, month: month, in: context).isEmpty {
                context.insert(makeExpense(bill: bill, month: month, now: now))
            }
        } else {
            bill.paidMonths.removeAll { $0 == month }
            for e in linkedExpenses(bill: bill, month: month, in: context) { context.delete(e) }
        }
        try? context.save()
    }

    /// Deletes an expense. If it was a bill payment, that bill is marked unpaid for its month.
    static func delete(_ expense: Expense, in context: ModelContext) {
        if let id = expense.billID, let month = expense.billMonth,
           let bill = ((try? context.fetch(FetchDescriptor<Bill>())) ?? []).first(where: { $0.id == id }) {
            bill.paidMonths.removeAll { $0 == month }
        }
        context.delete(expense)
        try? context.save()
    }

    /// Adds the missing expense for every month a bill is ticked paid
    /// (covers bills ticked before this feature existed). Safe to run on every launch.
    static func sync(in context: ModelContext, now: Date = .now) {
        let bills = (try? context.fetch(FetchDescriptor<Bill>())) ?? []
        var changed = false
        for bill in bills {
            for month in bill.paidMonths where linkedExpenses(bill: bill, month: month, in: context).isEmpty {
                context.insert(makeExpense(bill: bill, month: month, now: now))
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    private static func linkedExpenses(bill: Bill, month: String, in context: ModelContext) -> [Expense] {
        let billID = bill.id
        let all = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        return all.filter { $0.billID == billID && $0.billMonth == month }
    }

    private static func makeExpense(bill: Bill, month: String, now: Date) -> Expense {
        let e = Expense(amountCents: bill.amountCents, category: .bills, note: bill.name,
                        date: BudgetCalculator.billPaymentDate(month: month, now: now))
        e.billID = bill.id
        e.billMonth = month
        return e
    }
}
