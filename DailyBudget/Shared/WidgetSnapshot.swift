import Foundation

/// What the home-screen widget needs, saved by the app into the shared App Group.
/// It holds this month's (and later) everyday spending, so the widget can work out the
/// limit itself with BudgetCalculator, even on a new day before the app is opened.
struct WidgetSnapshot: Codable, Equatable {
    struct Item: Codable, Equatable {
        var date: Date
        var cents: Int
    }

    var livingMonthlyCents: Int
    /// Everyday (living) expenses from the start of the current month onward.
    var items: [Item]
    var updatedAt: Date
    /// Extra income added to living money, by month key. Optional so older snapshots still load.
    var extraLivingByMonth: [String: Int]? = nil

    static let appGroup = "group.com.pensereyotdom19.dailybudget"
    static let key = "widgetSnapshot.v1"

    func calculator(calendar: Calendar = .current) -> BudgetCalculator {
        BudgetCalculator(entries: items.map { .init(date: $0.date, cents: $0.cents, countsAsLiving: true) },
                         livingMonthlyCents: livingMonthlyCents, calendar: calendar,
                         extraLivingByMonth: extraLivingByMonth ?? [:])
    }

    static func load(from defaults: UserDefaults? = UserDefaults(suiteName: appGroup)) -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save(to defaults: UserDefaults? = UserDefaults(suiteName: appGroup)) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults?.set(data, forKey: Self.key)
    }
}
