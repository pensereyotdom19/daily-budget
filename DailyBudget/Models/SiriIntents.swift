import AppIntents
import Foundation

/// The everyday categories, for Siri and Shortcuts.
enum CategoryOption: String, AppEnum {
    case food, coffee, transport, sport, skinCare, phone, shopping, health, fun, other

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    /// Synonyms let Siri understand everyday words: "Add lunch", "Log Grab", "Add a top-up".
    static let caseDisplayRepresentations: [CategoryOption: DisplayRepresentation] = [
        .food: DisplayRepresentation(title: "Food", synonyms: ["lunch", "dinner", "breakfast", "meal", "snack", "rice", "noodles"]),
        .coffee: DisplayRepresentation(title: "Coffee", synonyms: ["a coffee", "latte", "iced coffee", "tea", "drink"]),
        .transport: DisplayRepresentation(title: "Transport", synonyms: ["Grab", "taxi", "tuk tuk", "PassApp", "bus", "fuel", "petrol", "gas"]),
        .sport: DisplayRepresentation(title: "Sport", synonyms: ["gym", "football", "badminton"]),
        .skinCare: DisplayRepresentation(title: "Skin care", synonyms: ["skincare", "cosmetics", "makeup"]),
        .phone: DisplayRepresentation(title: "Phone", synonyms: ["top-up", "top up", "phone top-up", "data", "phone card"]),
        .shopping: DisplayRepresentation(title: "Shopping", synonyms: ["clothes", "shoes", "groceries"]),
        .health: DisplayRepresentation(title: "Health", synonyms: ["medicine", "pharmacy", "doctor"]),
        .fun: DisplayRepresentation(title: "Fun", synonyms: ["movie", "cinema", "game", "games", "karaoke"]),
        .other: DisplayRepresentation(title: "Other", synonyms: ["something", "something else"]),
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

/// Siri only understands the exact phrases listed here (with any category word in place of the
/// category), so there are several ways to say each one. Every phrase must name the app.
struct DailyBudgetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddExpenseIntent(),
                    phrases: ["Add \(\.$category) in \(.applicationName)",
                              "Add \(\.$category) to \(.applicationName)",
                              "Add \(\.$category) on \(.applicationName)",
                              "Log \(\.$category) in \(.applicationName)",
                              "Log \(\.$category) to \(.applicationName)",
                              "Log \(\.$category) on \(.applicationName)",
                              "\(.applicationName) add \(\.$category)",
                              "\(.applicationName) log \(\.$category)",
                              "I bought \(\.$category) in \(.applicationName)",
                              "Spent on \(\.$category) in \(.applicationName)",
                              "Add an expense in \(.applicationName)",
                              "Add an expense to \(.applicationName)",
                              "Add expense in \(.applicationName)",
                              "Add expense to \(.applicationName)",
                              "Log an expense in \(.applicationName)",
                              "Log expense in \(.applicationName)",
                              "\(.applicationName) add expense"],
                    shortTitle: "Add expense", systemImageName: "plus.circle.fill")
        AppShortcut(intent: OpenAddExpenseIntent(),
                    phrases: ["New expense in \(.applicationName)",
                              "New \(.applicationName) expense",
                              "Open \(.applicationName) to add an expense",
                              "Open the add screen in \(.applicationName)"],
                    shortTitle: "New expense", systemImageName: "square.and.pencil")
    }
}
