import SwiftUI
import SwiftData

@main
struct DailyBudgetApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [Expense.self, Bill.self, BudgetSettings.self])
    }
}
