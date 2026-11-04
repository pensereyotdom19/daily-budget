import Foundation
import SwiftData

extension Notification.Name {
    /// Posted by Siri/Shortcuts actions that run inside the app, so an open app saves them at once.
    static let quickAddQueued = Notification.Name("quickAddQueued")
}

/// Saves expenses that were added from the widget or Siri while the app wasn't open.
@MainActor
enum QuickAddImporter {
    static let openAddKey = "quickAdd.openAddScreen"

    @discardableResult
    static func run(in context: ModelContext) -> Int {
        let pending = QuickAddQueue.takeAll()
        guard !pending.isEmpty else { return 0 }
        let existing = Set(((try? context.fetch(FetchDescriptor<Expense>())) ?? []).map(\.id))
        var added = 0
        for p in pending where !existing.contains(p.id) {
            let e = Expense(amountCents: p.cents, category: Category(rawValue: p.category) ?? .other, note: p.note, date: p.date)
            e.id = p.id
            context.insert(e)
            added += 1
        }
        try? context.save()
        return added
    }

    /// True once if a Shortcut asked to open the + screen.
    static func takeOpenAddRequest() -> Bool {
        let d = UserDefaults(suiteName: WidgetSnapshot.appGroup)
        guard d?.bool(forKey: openAddKey) == true else { return false }
        d?.removeObject(forKey: openAddKey)
        return true
    }
}
