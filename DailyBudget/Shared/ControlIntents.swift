import AppIntents
import Foundation

/// Opens the app on the + screen. Used by the "New expense" control (Control Center / Lock Screen).
/// It lives in both the app and the widget so the control can open the app.
struct NewExpenseFromControlIntent: AppIntent {
    static let title: LocalizedStringResource = "New expense"
    static let description = IntentDescription("Opens Daily Budget ready to add an expense.")
    static let openAppWhenRun = true
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: WidgetSnapshot.appGroup)?.set(true, forKey: "quickAdd.openAddScreen")
        return .result()
    }
}

/// Adds the thing you log most often (from the app's quick-add list) without opening the app.
struct QuickAddTopIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick add"
    static let description = IntentDescription("Adds the expense you log most often.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        guard let item = WidgetSnapshot.load()?.quickItems?.first, item.cents > 0 else { return .result() }
        let pending = PendingExpense(id: UUID(), cents: item.cents, category: item.category, note: item.note, date: .now)
        QuickAddQueue.append(pending)
        QuickAddQueue.applyToSnapshot(pending, countsAsLiving: QuickAddQueue.countsAsLiving(item.category))
        return .result()
    }
}
