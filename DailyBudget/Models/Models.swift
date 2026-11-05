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
    /// Set when this expense was created by ticking a bill paid (see BillPayments).
    var billID: UUID? = nil
    /// The month key ("2026-11") of that bill payment.
    var billMonth: String? = nil

    init(amountCents: Int, category: Category, note: String = "", date: Date = .now) {
        self.id = UUID()
        self.amountCents = amountCents
        self.categoryRaw = category.rawValue
        self.note = note
        self.date = date
    }

    /// The server refuses longer notes, so the app stops typing there too.
    static let maxNoteLength = 200

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
    /// Day of the month it is paid automatically (1–31). Nil: you tick it paid yourself.
    var dueDay: Int? = nil
    /// The last month the app paid it automatically, so unticking by hand sticks.
    var lastAutoMonth: String? = nil

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
    // Mark paid/unpaid through BillPayments so the matching Bills expense is kept in step.
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
    /// First month shown in History. Set when a new plan starts, so earlier months stay visible.
    var historyStartMonth: String? = nil
    /// Emergency savings carried over from earlier plans.
    var savedBeforeCents: Int = 0
    /// Monthly limit per category as JSON ({"coffee":1500}); use `categoryLimits`.
    var categoryLimitsJSON: String = ""

    init() {}
}

/// Where extra money goes when it comes in.
enum IncomeTarget: String, CaseIterable, Codable, Identifiable {
    case living, savings, engagement
    var id: String { rawValue }
}

/// Extra money you received (a gift, a side job). Amount in cents.
@Model
final class Income {
    var id: UUID = UUID()
    var amountCents: Int = 0
    var note: String = ""
    var date: Date = Date()
    var targetRaw: String = IncomeTarget.living.rawValue

    init(amountCents: Int, target: IncomeTarget, note: String = "", date: Date = .now) {
        self.id = UUID()
        self.amountCents = amountCents
        self.targetRaw = target.rawValue
        self.note = note
        self.date = date
    }

    var target: IncomeTarget {
        get { IncomeTarget(rawValue: targetRaw) ?? .living }
        set { targetRaw = newValue.rawValue }
    }
}

/// An expense that repeats every month on the same day (not a bill), e.g. a phone top-up.
@Model
final class RecurringExpense {
    var id: UUID = UUID()
    var amountCents: Int = 0
    var categoryRaw: String = Category.other.rawValue
    var note: String = ""
    /// 1–31. Short months use their last day.
    var dayOfMonth: Int = 1
    /// First month it applies to ("2026-11").
    var startMonth: String = ""
    /// The last month it was added for, so it is never added twice.
    var lastAddedMonth: String? = nil
    var isActive: Bool = true

    init(amountCents: Int, category: Category, note: String, dayOfMonth: Int, startMonth: String) {
        self.id = UUID()
        self.amountCents = amountCents
        self.categoryRaw = category.rawValue
        self.note = note
        self.dayOfMonth = dayOfMonth
        self.startMonth = startMonth
    }

    var category: Category {
        get { Category(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}

/// A service you pay for regularly (Netflix, Spotify, iCloud…). Paid from planned money like a bill;
/// the app adds the payment as a Bills expense on each renewal date.
@Model
final class Subscription {
    var id: UUID = UUID()
    var name: String = ""
    var amountCents: Int = 0
    /// "monthly" or "yearly".
    var cycleRaw: String = SubscriptionCycle.monthly.rawValue
    /// The next date it renews (and gets added as an expense).
    var nextRenewal: Date = Date()
    /// Day of the month it renews on (kept so Jan 31 → Feb 28 → Mar 31).
    var anchorDay: Int = 1
    /// First month it costs money ("2026-11").
    var startMonth: String = ""
    var isActive: Bool = true

    init(name: String, amountCents: Int, cycle: SubscriptionCycle, nextRenewal: Date, calendar: Calendar = .current) {
        self.id = UUID()
        self.name = name
        self.amountCents = amountCents
        self.cycleRaw = cycle.rawValue
        self.nextRenewal = nextRenewal
        self.anchorDay = calendar.component(.day, from: nextRenewal)
        self.startMonth = MonthKey.key(for: nextRenewal, calendar: calendar)
    }

    var cycle: SubscriptionCycle {
        get { SubscriptionCycle(rawValue: cycleRaw) ?? .monthly }
        set { cycleRaw = newValue.rawValue }
    }
}

enum SubscriptionCycle: String, CaseIterable, Codable, Identifiable {
    case monthly, yearly
    var id: String { rawValue }
}
