import Foundation

/// One-tap suggestions for the Today screen, learned from what you log most often.
enum QuickAdd {
    struct Past {
        var category: Category
        var note: String
        var cents: Int
        var date: Date
    }

    struct Item: Hashable, Identifiable {
        var category: Category
        var note: String
        var cents: Int
        var id: String { "\(category.rawValue)|\(note.lowercased())|\(cents)" }
        var title: String { note.isEmpty ? category.title : note }
    }

    /// The most frequent (category, note, amount) combinations of the last `days` days,
    /// most used first, ties broken by the most recent. Bills and Engagement are left out.
    static func suggestions(from past: [Past], now: Date = .now, days: Int = 60, limit: Int = 6,
                            calendar: Calendar = .current) -> [Item] {
        let since = calendar.date(byAdding: .day, value: -days, to: now) ?? now
        var stats: [String: (item: Item, count: Int, last: Date)] = [:]
        for p in past where p.category != .bills && p.category != .engagement && p.date >= since && p.cents > 0 {
            let item = Item(category: p.category, note: p.note.trimmingCharacters(in: .whitespaces), cents: p.cents)
            if let s = stats[item.id] {
                stats[item.id] = (s.item, s.count + 1, max(s.last, p.date))
            } else {
                stats[item.id] = (item, 1, p.date)
            }
        }
        return stats.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.last > $1.last }
            .prefix(limit)
            .map(\.item)
    }
}
