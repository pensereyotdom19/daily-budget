import Foundation

/// Matches expenses by note, category name (in the app's language) or amount.
enum ExpenseSearch {
    static func filter(_ expenses: [Expense], query: String) -> [Expense] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let cents = Money.parse(q.replacingOccurrences(of: "$", with: ""))
        return expenses.filter { matches(note: $0.note, category: $0.category.title, cents: $0.amountCents, query: q, queryCents: cents) }
    }

    /// Case- and accent-insensitive; "1.25" or "$1.25" also finds that exact amount.
    static func matches(note: String, category: String, cents: Int, query: String, queryCents: Int?) -> Bool {
        if let queryCents, queryCents == cents { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return note.range(of: query, options: options) != nil || category.range(of: query, options: options) != nil
    }
}
