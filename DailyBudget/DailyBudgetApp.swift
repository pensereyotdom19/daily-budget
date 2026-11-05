import SwiftUI
import SwiftData

@main
struct DailyBudgetApp: App {
    @State private var sync = SyncManager()
    @State private var lock = AppLock()
    /// Opens on Today. For screenshots during development, launch with `-startTab history` (or plan, settings).
    @State private var tab = AppTab(rawValue: UserDefaults.standard.string(forKey: "startTab") ?? "") ?? .today
    @AppStorage(AppLanguage.key, store: UserDefaults(suiteName: WidgetSnapshot.appGroup)) private var language = AppLanguage.system.rawValue

    init() {
        AppLanguage.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView(tab: $tab)
                .environment(sync)
                .environment(lock)
                .environment(\.locale, AppLanguage.locale)
                // A new language redraws every screen, so all text and dates switch at once.
                .id(language)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [Expense.self, Bill.self, BudgetSettings.self, Income.self, RecurringExpense.self, Subscription.self])
    }
}
