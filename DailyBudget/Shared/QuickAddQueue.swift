import Foundation

/// Expenses added from outside the app (the widget's buttons, Siri, Shortcuts) wait here, in the shared
/// App Group, until the app opens and saves them like any other expense (then they sync as usual).
struct PendingExpense: Codable, Equatable {
    var id: UUID
    var cents: Int
    var category: String
    var note: String
    var date: Date
}

/// A quick-add button shown on the widget: the app's most-used items.
struct WidgetQuickItem: Codable, Equatable, Hashable {
    var title: String
    var note: String
    var category: String
    var cents: Int
    var symbol: String
    var colorHex: UInt32
}

enum QuickAddQueue {
    static let key = "quickAdd.pending.v1"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshot.appGroup) }

    static func append(_ item: PendingExpense, to store: UserDefaults? = defaults) {
        var list = load(from: store)
        guard !list.contains(where: { $0.id == item.id }) else { return }
        list.append(item)
        if let data = try? JSONEncoder().encode(Array(list.suffix(200))) { store?.set(data, forKey: key) }
    }

    static func load(from store: UserDefaults? = defaults) -> [PendingExpense] {
        guard let data = store?.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PendingExpense].self, from: data)) ?? []
    }

    /// Returns everything waiting and empties the queue.
    static func takeAll(from store: UserDefaults? = defaults) -> [PendingExpense] {
        let list = load(from: store)
        store?.removeObject(forKey: key)
        return list
    }

    /// Adds the expense to the widget's numbers straight away (everyday categories only), so the ring
    /// shows the new "left today" before the app is opened.
    static func applyToSnapshot(_ item: PendingExpense, countsAsLiving: Bool) {
        guard countsAsLiving, var snap = WidgetSnapshot.load() else { return }
        snap.items.append(.init(date: item.date, cents: item.cents))
        snap.save()
    }

    /// Bills and Engagement aren't everyday money.
    static func countsAsLiving(_ category: String) -> Bool {
        category != "bills" && category != "engagement"
    }
}
