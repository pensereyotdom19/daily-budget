import Foundation
import SwiftData

/// Marks bills with a due day paid on that day, adding the payment as a Bills expense dated that day.
/// Runs when the app opens; a missed day is caught up next time.
@MainActor
enum BillAutoPay {
    @discardableResult
    static func run(in context: ModelContext, now: Date = .now) -> Int {
        let bills = (try? context.fetch(FetchDescriptor<Bill>())) ?? []
        var paid = 0
        for bill in bills {
            guard let day = bill.dueDay else { continue }
            let months = BillSchedule.monthsToHandle(dueMonths: bill.dueMonths, dueDay: day,
                                                     lastAutoMonth: bill.lastAutoMonth, now: now)
            for month in months where !bill.isPaid(in: month) {
                BillPayments.setPaid(true, bill: bill, month: month, in: context, now: now,
                                     date: BillSchedule.dueDate(month: month, day: day))
                paid += 1
            }
            if let last = months.last { bill.lastAutoMonth = last }
        }
        if paid > 0 || context.hasChanges { try? context.save() }
        return paid
    }

    /// Sets or clears a bill's due day. A new due day only acts from this month on.
    static func setDueDay(_ day: Int?, for bill: Bill, in context: ModelContext, now: Date = .now) {
        if day != nil && bill.dueDay == nil {
            bill.lastAutoMonth = BillSchedule.startingLastAutoMonth(now: now)
        }
        bill.dueDay = day
        try? context.save()
        run(in: context, now: now)
    }
}
