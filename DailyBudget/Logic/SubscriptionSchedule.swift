import Foundation

/// Renewal dates and planned costs for subscriptions.
enum SubscriptionSchedule {
    /// The renewal after `date`: same day next month (or next year), using the anchor day so
    /// a subscription on the 31st renews on the last day of shorter months and goes back to the 31st.
    static func next(after date: Date, cycle: SubscriptionCycle, anchorDay: Int, calendar: Calendar = .current) -> Date {
        let step = cycle == .monthly ? DateComponents(month: 1) : DateComponents(year: 1)
        let time = calendar.dateComponents([.hour, .minute], from: date)
        guard let shifted = calendar.date(byAdding: step, to: date),
              let monthStart = calendar.dateInterval(of: .month, for: shifted)?.start,
              let length = calendar.range(of: .day, in: .month, for: shifted)?.count else { return date }
        let day = min(max(1, anchorDay), length)
        return calendar.date(byAdding: DateComponents(day: day - 1, hour: time.hour ?? 9, minute: time.minute ?? 0),
                             to: monthStart) ?? shifted
    }

    /// Every renewal up to `now`, starting at `nextRenewal`, and the renewal after the last one.
    static func due(nextRenewal: Date, cycle: SubscriptionCycle, anchorDay: Int, now: Date,
                    calendar: Calendar = .current) -> (dates: [Date], next: Date) {
        var dates: [Date] = []
        var date = nextRenewal
        while date <= now, dates.count < 60 {
            dates.append(date)
            date = next(after: date, cycle: cycle, anchorDay: anchorDay, calendar: calendar)
        }
        return (dates, date)
    }

    /// The months of `months` it costs money in: every month from `startMonth` (monthly), or once a year
    /// in its renewal month (yearly). A stopped subscription only counts in months already past.
    static func dueMonths(in months: [String], cycle: SubscriptionCycle, startMonth: String, renewalMonth: Int,
                          isActive: Bool, currentMonth: String) -> [String] {
        months.filter { m in
            guard m >= startMonth, isActive || m < currentMonth else { return false }
            if cycle == .monthly { return true }
            return MonthKey.components(of: m)?.month == renewalMonth
        }
    }

    /// Average cost per month: monthly price, or yearly price ÷ 12 (rounded to the cent).
    static func monthlyCents(amountCents: Int, cycle: SubscriptionCycle) -> Int {
        cycle == .monthly ? amountCents : (amountCents + 6) / 12
    }

    /// A symbol for well-known services, guessed from the name.
    static func symbol(for name: String) -> String {
        let n = name.lowercased()
        let table: [([String], String)] = [
            (["netflix", "disney", "hbo", "prime video", "tv"], "tv.fill"),
            (["spotify", "music", "apple music", "joox"], "music.note"),
            (["youtube"], "play.rectangle.fill"),
            (["icloud", "google one", "dropbox", "drive", "storage"], "icloud.fill"),
            (["chatgpt", "claude", "openai", "ai"], "sparkles"),
            (["gym", "fitness"], "figure.run"),
            (["game", "xbox", "playstation", "nintendo"], "gamecontroller.fill"),
            (["news", "medium", "book", "kindle"], "book.fill"),
            (["vpn", "1password", "password"], "lock.shield.fill"),
            (["phone", "mobile", "smart", "cellcard", "metfone"], "phone.fill"),
            (["internet", "wifi"], "wifi"),
        ]
        return table.first { $0.0.contains { n.contains($0) } }?.1 ?? "repeat.circle.fill"
    }
}

extension Subscription {
    func dueMonths(in months: [String], now: Date = .now, calendar: Calendar = .current) -> [String] {
        SubscriptionSchedule.dueMonths(in: months, cycle: cycle, startMonth: startMonth,
                                       renewalMonth: calendar.component(.month, from: nextRenewal),
                                       isActive: isActive, currentMonth: MonthKey.key(for: now, calendar: calendar))
    }

    var monthlyCents: Int { SubscriptionSchedule.monthlyCents(amountCents: amountCents, cycle: cycle) }
    var symbol: String { SubscriptionSchedule.symbol(for: name) }

    /// For planned-cost sums: (price, months it's due in).
    func asPlanned(in months: [String]) -> (cents: Int, dueMonths: [String]) {
        (amountCents, dueMonths(in: months))
    }
}
