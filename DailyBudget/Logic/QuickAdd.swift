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

    /// The category you usually log at this time of day (within 1½ hours, last 60 days, at least
    /// twice). Without enough history: coffee in the morning, food otherwise.
    static func guessCategory(from past: [Past], now: Date = .now, calendar: Calendar = .current) -> Category {
        func minutes(_ d: Date) -> Int {
            let c = calendar.dateComponents([.hour, .minute], from: d)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        let since = calendar.date(byAdding: .day, value: -60, to: now) ?? now
        let nowMin = minutes(now)
        var counts: [Category: Int] = [:]
        for p in past where p.date >= since && p.date <= now && p.category.countsAsLiving && abs(minutes(p.date) - nowMin) <= 90 {
            counts[p.category, default: 0] += 1
        }
        if let best = counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue }),
           best.value >= 2 {
            return best.key
        }
        let hour = calendar.component(.hour, from: now)
        return (5..<11).contains(hour) ? .coffee : .food
    }

    /// Notes you've used before that contain what you're typing, same category first, then most used.
    static func noteSuggestions(from past: [Past], typed: String, category: Category?, limit: Int = 3) -> [Item] {
        let q = typed.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var seen: [String: (item: Item, count: Int, last: Date)] = [:]
        for p in past where !p.note.isEmpty && p.category != .bills && p.category != .engagement {
            let note = p.note.trimmingCharacters(in: .whitespaces)
            guard note.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil,
                  note.caseInsensitiveCompare(q) != .orderedSame else { continue }
            let key = note.lowercased()
            if let s = seen[key] {
                // Keep the most recent price and category for this note.
                let newer = p.date > s.last
                seen[key] = (newer ? Item(category: p.category, note: note, cents: p.cents) : s.item, s.count + 1, max(s.last, p.date))
            } else {
                seen[key] = (Item(category: p.category, note: note, cents: p.cents), 1, p.date)
            }
        }
        return seen.values.sorted { a, b in
            let ac = a.item.category == category, bc = b.item.category == category
            if ac != bc { return ac }
            return a.count != b.count ? a.count > b.count : a.last > b.last
        }
        .prefix(limit).map(\.item)
    }
}
