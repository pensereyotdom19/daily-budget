import SwiftUI
import SwiftData

@main
struct DailyBudgetApp: App {
    @State private var sync = SyncManager()
    @State private var lock = AppLock()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(sync)
                .environment(lock)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [Expense.self, Bill.self, BudgetSettings.self, Income.self, RecurringExpense.self])
    }
}
