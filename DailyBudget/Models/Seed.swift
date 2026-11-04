import Foundation
import SwiftData

/// Pre-fills the app with the 6-month plan (Nov 2026 – Apr 2027) the first time it opens.
enum Seed {
    static func insertIfNeeded(into context: ModelContext) {
        if let existing = try? context.fetch(FetchDescriptor<BudgetSettings>()).first {
            // Installs from before firstOpenedAt existed start their streak today.
            if existing.firstOpenedAt == nil {
                existing.firstOpenedAt = .now
                try? context.save()
            }
            return
        }

        let settings = BudgetSettings()
        settings.firstOpenedAt = .now
        context.insert(settings)

        let months = MonthKey.range(start: settings.startMonth, count: settings.monthCount)
        // months = ["2026-11", "2026-12", "2027-01", "2027-02", "2027-03", "2027-04"]
        let bills: [(String, Int, [String])] = [
            ("Bank", 20_000, months),
            ("Electricity", 10_000, months),
            ("Wifi", 1_800, months),
            ("Waste management", 500, months),
            ("Water", 500, [months[0], months[3]]),          // every 3 months
            ("Credit card", 70_000, [months[1]]),              // one time, December
        ]
        for (i, b) in bills.enumerated() {
            context.insert(Bill(name: b.0, amountCents: b.1, dueMonths: b.2, sortOrder: i))
        }
        try? context.save()
    }
}
