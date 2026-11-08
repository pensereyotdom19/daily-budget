#if DEBUG
import Foundation
import SwiftData

/// Development only: launch with `-sampleData YES` (simulator screenshots) to fill an empty install
/// with a week of believable spending. Never runs unless that option is passed, and never in release builds.
@MainActor
enum SampleData {
    static func insertIfRequested(into context: ModelContext, now: Date = .now) {
        guard UserDefaults.standard.bool(forKey: "sampleData") else { return }
        let existing = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        guard existing.isEmpty else { return }
        let cal = Calendar.current
        func at(_ daysAgo: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: now))!
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        let items: [(Int, Int, Int, Category, String, Int)] = [
            (0, 8, 15, .coffee, "Iced coffee", 125), (0, 12, 30, .food, "Rice and pork", 150), (0, 18, 5, .transport, "Grab", 100),
            (1, 9, 0, .coffee, "Iced coffee", 125), (1, 13, 0, .food, "Noodles", 200), (1, 19, 0, .fun, "Movie", 350),
            (2, 8, 30, .coffee, "Iced coffee", 125), (2, 12, 15, .food, "Coconut", 85),
            (3, 12, 0, .food, "Lunch", 175), (3, 17, 0, .phone, "Top-up", 100),
            (4, 9, 0, .coffee, "Latte", 150), (4, 13, 0, .food, "Rice", 150),
        ]
        for (ago, h, m, cat, note, cents) in items where at(ago, h, m) <= now {
            context.insert(Expense(amountCents: cents, category: cat, note: note, date: at(ago, h, m)))
        }
        if let renew = cal.date(byAdding: .day, value: 9, to: now) {
            context.insert(Subscription(name: "YouTube Premium", amountCents: 299, cycle: .monthly, nextRenewal: renew))
        }
        if let renew = cal.date(byAdding: .day, value: 20, to: now) {
            context.insert(Subscription(name: "Claude Pro", amountCents: 2000, cycle: .monthly, nextRenewal: renew))
        }
        context.insert(Income(amountCents: 2000, target: .savings, note: "Gift from mom", date: at(2, 10)))
        // Count the whole month so History's calendar and day list have something to show.
        if let settings = try? context.fetch(FetchDescriptor<BudgetSettings>()).first,
           let monthStart = cal.dateInterval(of: .month, for: now)?.start {
            settings.firstOpenedAt = monthStart
        }
        try? context.save()
    }
}
#endif
