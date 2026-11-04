import AppIntents
import Foundation

/// The everyday categories, for Siri and Shortcuts.
enum CategoryOption: String, AppEnum {
    case food, coffee, transport, sport, skinCare, phone, shopping, health, fun, other

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static let caseDisplayRepresentations: [CategoryOption: DisplayRepresentation] = [
        .food: "Food", .coffee: "Coffee", .transport: "Transport", .sport: "Sport", .skinCare: "Skin care",
        .phone: "Phone", .shopping: "Shopping", .health: "Health", .fun: "Fun", .other: "Other",
    ]
}

/// "Hey Siri, add coffee in Daily Budget". Without an amount it uses the usual price for that category.
struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add expense"
    static let description = IntentDescription("Logs an expense in Daily Budget.")

    @Parameter(title: "Category") var category: CategoryOption
    @Parameter(title: "Amount", description: "In US dollars") var amount: Double?
    @Parameter(title: "Note") var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) for \(\.$category)") { \.$note }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let usual = WidgetSnapshot.load()?.quickItems?.first { $0.category == category.rawValue }
        let cents: Int
        if let amount {
            cents = Int((amount * 100).rounded())
        } else if let usual {
            cents = usual.cents
        } else {
            throw $amount.needsValueError("How much was it, in dollars?")
        }
        guard cents > 0, cents < 100_000_000 else { throw $amount.needsValueError("How much was it, in dollars?") }

        let text = String((note ?? (amount == nil ? usual?.note : nil) ?? "").prefix(Expense.maxNoteLength))
        let pending = PendingExpense(id: UUID(), cents: cents, category: category.rawValue, note: text, date: .now)
        QuickAddQueue.append(pending)
        QuickAddQueue.applyToSnapshot(pending, countsAsLiving: true)
        NotificationCenter.default.post(name: .quickAddQueued, object: nil)

        let title = Category(rawValue: category.rawValue)?.title ?? category.rawValue
        if let snap = WidgetSnapshot.load() {
            let left = snap.calculator().summary(on: .now).leftCents
            return .result(dialog: "Added \(title) \(Money.format(cents, alwaysShowCents: true)). \(Money.format(left, alwaysShowCents: true)) left today.")
        }
        return .result(dialog: "Added \(title) \(Money.format(cents, alwaysShowCents: true)).")
    }
}

/// Opens the app on the + screen. Handy for the Action Button or Back Tap via Shortcuts.
struct OpenAddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "New expense"
    static let description = IntentDescription("Opens Daily Budget ready to add an expense.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: WidgetSnapshot.appGroup)?.set(true, forKey: QuickAddImporter.openAddKey)
        NotificationCenter.default.post(name: .quickAddQueued, object: nil)
        return .result()
    }
}

struct DailyBudgetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddExpenseIntent(),
                    phrases: ["Add \(\.$category) in \(.applicationName)",
                              "Log \(\.$category) in \(.applicationName)",
                              "Add an expense in \(.applicationName)"],
                    shortTitle: "Add expense", systemImageName: "plus.circle.fill")
        AppShortcut(intent: OpenAddExpenseIntent(),
                    phrases: ["New expense in \(.applicationName)", "Open \(.applicationName) to add an expense"],
                    shortTitle: "New expense", systemImageName: "square.and.pencil")
    }
}
