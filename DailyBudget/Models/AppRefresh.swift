import Foundation
import SwiftData
import UserNotifications
import WidgetKit

/// Keeps things outside the app in step with your data: the widget and the reminders.
/// Runs when the app opens and when you leave it.
@MainActor
enum AppRefresh {
    static func run(context: ModelContext, now: Date = .now) {
        let expenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        let settings = (try? context.fetch(FetchDescriptor<BudgetSettings>()))?.first
        let bills = (try? context.fetch(FetchDescriptor<Bill>())) ?? []
        let incomes = (try? context.fetch(FetchDescriptor<Income>())) ?? []
        WidgetSync.update(expenses: expenses, settings: settings, incomes: incomes, now: now)
        let subscriptions = (try? context.fetch(FetchDescriptor<Subscription>())) ?? []
        ReminderScheduler.refresh(expenses: expenses, settings: settings, incomes: incomes, bills: bills,
                                  subscriptions: subscriptions, now: now)
    }
}

enum WidgetSync {
    static func snapshot(expenses: [Expense], settings: BudgetSettings?, incomes: [Income] = [], now: Date,
                         calendar: Calendar = .current) -> WidgetSnapshot {
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let items = expenses
            .filter { $0.category.countsAsLiving && $0.date >= monthStart }
            .map { WidgetSnapshot.Item(date: $0.date, cents: $0.amountCents) }
            .sorted { $0.date < $1.date }
        let extra = Income.byMonth(incomes, target: .living, calendar: calendar)
        let quick = QuickAdd.suggestions(from: expenses.filter { $0.billID == nil }
            .map { QuickAdd.Past(category: $0.category, note: $0.note, cents: $0.amountCents, date: $0.date) }, now: now, limit: 3)
            .map { WidgetQuickItem(title: $0.title, note: $0.note, category: $0.category.rawValue, cents: $0.cents,
                                   symbol: $0.category.symbol, colorHex: $0.category.hex) }
        return WidgetSnapshot(livingMonthlyCents: settings?.livingMonthlyCents ?? 9_200, items: items, updatedAt: now,
                              extraLivingByMonth: extra.isEmpty ? nil : extra, quickItems: quick.isEmpty ? nil : quick)
    }

    static func update(expenses: [Expense], settings: BudgetSettings?, incomes: [Income], now: Date) {
        let new = snapshot(expenses: expenses, settings: settings, incomes: incomes, now: now)
        var old = WidgetSnapshot.load()
        old?.updatedAt = new.updatedAt
        guard old != new else { return }  // nothing changed: don't spend the widget's reload budget
        new.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Reminder switches, saved on this phone (UserDefaults).
enum ReminderPrefs {
    static let morningOn = "remind.morningOn"
    static let morningMinutes = "remind.morningMinutes"
    static let eveningOn = "remind.eveningOn"
    static let eveningMinutes = "remind.eveningMinutes"
    static let billsOn = "remind.billsOn"
    static let weeklyOn = "remind.weeklyOn"
    static let expiryOn = "remind.expiryOn"
    static let subscriptionsOn = "remind.subscriptionsOn"

    static func current(_ d: UserDefaults = .standard) -> ReminderPlanner.Settings {
        var s = ReminderPlanner.Settings()
        s.morningOn = d.bool(forKey: morningOn)
        s.eveningOn = d.bool(forKey: eveningOn)
        s.billsOn = d.bool(forKey: billsOn)
        s.weeklyOn = d.bool(forKey: weeklyOn)
        s.expiryOn = d.bool(forKey: expiryOn)
        s.subscriptionsOn = d.bool(forKey: subscriptionsOn)
        if d.object(forKey: morningMinutes) != nil { s.morningMinutes = d.integer(forKey: morningMinutes) }
        if d.object(forKey: eveningMinutes) != nil { s.eveningMinutes = d.integer(forKey: eveningMinutes) }
        return s
    }
}

enum ReminderScheduler {
    /// Asks iOS for permission to show notifications. Returns whether it's allowed.
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    static func refresh(expenses: [Expense], settings: BudgetSettings?, incomes: [Income], bills: [Bill],
                        subscriptions: [Subscription] = [], now: Date,
                        calendar: Calendar = .current) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let prefs = ReminderPrefs.current()
        guard prefs.anyOn else { return }

        let loggedToday = expenses.contains { calendar.isDate($0.date, inSameDayAs: now) && $0.billID == nil }
        let dues = bills.flatMap { bill in
            bill.dueMonths.map { ReminderPlanner.BillDue(name: bill.name, cents: bill.amountCents,
                                                         month: $0, isPaid: bill.isPaid(in: $0), dueDay: bill.dueDay) }
        }
        let plan = ReminderPlanner.plan(now: now, settings: prefs,
                                        calculator: BudgetCalculator(expenses: expenses, settings: settings, incomes: incomes),
                                        loggedToday: loggedToday, bills: dues,
                                        planMonths: settings?.planMonths ?? [],
                                        appExpiresAt: AppExpiry.date,
                                        streakStart: settings?.streakStartDate ?? .distantPast,
                                        categoryTitle: { (Category(rawValue: $0) ?? .other).title },
                                        renewals: subscriptions.filter(\.isActive).map {
                                            .init(id: $0.id, name: $0.name, cents: $0.amountCents, date: $0.nextRenewal)
                                        })
        for r in plan {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: r.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: trigger))
        }
    }
}
