import Foundation
import SwiftData

/// Adds each subscription payment as a Bills expense on its renewal date. Runs when the app opens.
@MainActor
enum SubscriptionRunner {
    @discardableResult
    static func addDue(in context: ModelContext, now: Date = .now) -> Int {
        let list = (try? context.fetch(FetchDescriptor<Subscription>())) ?? []
        var added = 0
        for s in list where s.isActive {
            let due = SubscriptionSchedule.due(nextRenewal: s.nextRenewal, cycle: s.cycle, anchorDay: s.anchorDay, now: now)
            for date in due.dates {
                context.insert(Expense(amountCents: s.amountCents, category: .bills, note: s.name, date: date))
                added += 1
            }
            if !due.dates.isEmpty { s.nextRenewal = due.next }
        }
        if added > 0 { try? context.save() }
        return added
    }
}
