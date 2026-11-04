import Foundation
import SwiftData

/// Adds recurring expenses whose day has come. Runs when the app opens.
@MainActor
enum RecurringRunner {
    @discardableResult
    static func addDue(in context: ModelContext, now: Date = .now) -> Int {
        let list = (try? context.fetch(FetchDescriptor<RecurringExpense>())) ?? []
        var added = 0
        for r in list where r.isActive {
            for due in RecurringSchedule.due(dayOfMonth: r.dayOfMonth, startMonth: r.startMonth,
                                             lastAddedMonth: r.lastAddedMonth, now: now) {
                context.insert(Expense(amountCents: r.amountCents, category: r.category, note: r.note, date: due.date))
                r.lastAddedMonth = due.month
                added += 1
            }
        }
        if added > 0 { try? context.save() }
        return added
    }
}
