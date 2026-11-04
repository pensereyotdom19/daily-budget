import SwiftUI
import SwiftData

@main
struct DailyBudgetApp: App {
    @State private var sync = SyncManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(sync)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [Expense.self, Bill.self, BudgetSettings.self])
    }
}
