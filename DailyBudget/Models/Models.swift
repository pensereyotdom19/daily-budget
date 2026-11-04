import Foundation
import SwiftData

/// One thing you spent money on. Amounts are stored in cents to avoid rounding errors.
@Model
final class Expense {
    var id: UUID = UUID()
    var amountCents: Int = 0
    var categoryRaw: String = Category.other.rawValue
    var note: String = ""
    var date: Date = Date()

    init(amountCents: Int, category: Category, note: String = "", date: Date = .now) {
        self.id = UUID()
        self.amountCents = amountCents
        self.categoryRaw = category.rawValue
        self.note = note
        self.date = date
    }

    var category: Category {
        get { Category(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}

/// A planned bill. `dueMonths` holds month keys like "2026-11" for each month it is due.
@Model
final class Bill {
    var id: UUID = UUID()
    var name: String = ""
    var amountCents: Int = 0
    var dueMonths: [String] = []
    var paidMonths: [String] = []
    var sortOrder: Int = 0

    init(name: String, amountCents: Int, dueMonths: [String], sortOrder: Int) {
        self.id = UUID()
        self.name = name
        self.amountCents = amountCents
        self.dueMonths = dueMonths
        self.paidMonths = []
        self.sortOrder = sortOrder
    }

    func isDue(in monthKey: String) -> Bool { dueMonths.contains(monthKey) }
    func isPaid(in monthKey: String) -> Bool { paidMonths.contains(monthKey) }

    func togglePaid(in monthKey: String) {
        if let i = paidMonths.firstIndex(of: monthKey) {
            paidMonths.remove(at: i)
        } else {
            paidMonths.append(monthKey)
        }
    }
}

/// The overall 6-month plan. There is exactly one.
@Model
final class BudgetSettings {
    var startMonth: String = "2026-11"
    var monthCount: Int = 6
    var totalCents: Int = 470_000
    var livingMonthlyCents: Int = 9_200
    var engagementCents: Int = 150_000
    /// When the app was first opened. The on-budget streak never counts days before this.
    var firstOpenedAt: Date? = nil

    init() {}
}
