import Foundation

/// When a monthly recurring expense should be added.
enum RecurringSchedule {
    /// Every month from `startMonth` (or the month after `lastAddedMonth`) up to now whose day has come,
    /// with the date to use. The day is moved to the month's last day in short months (31 → Feb 28).
    static func due(dayOfMonth: Int, startMonth: String, lastAddedMonth: String?, now: Date,
                    calendar: Calendar = .current) -> [(month: String, date: Date)] {
        let currentKey = MonthKey.key(for: now, calendar: calendar)
        var month = startMonth
        if let last = lastAddedMonth, last >= startMonth {
            month = MonthKey.range(start: last, count: 2)[1]
        }
        var out: [(String, Date)] = []
        while month <= currentKey, out.count < 24 {
            if let date = date(in: month, day: dayOfMonth, calendar: calendar), date <= now {
                out.append((month, date))
            }
            month = MonthKey.range(start: month, count: 2)[1]
        }
        return out
    }

    /// 9 AM on that day of the month, clamped to the month's length.
    static func date(in month: String, day: Int, calendar: Calendar = .current) -> Date? {
        guard let first = MonthKey.firstDay(of: month, calendar: calendar),
              let length = calendar.range(of: .day, in: .month, for: first)?.count else { return nil }
        let d = min(max(1, day), length)
        return calendar.date(byAdding: DateComponents(day: d - 1, hour: 9), to: first)
    }
}
