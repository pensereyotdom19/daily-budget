import Foundation

/// Bills with a due day are paid automatically on that day of each month they're due.
enum BillSchedule {
    /// 9 AM on `day` of `month`, moved to the month's last day when the month is shorter.
    static func dueDate(month: String, day: Int, calendar: Calendar = .current) -> Date? {
        guard let first = MonthKey.firstDay(of: month, calendar: calendar),
              let length = calendar.range(of: .day, in: .month, for: first)?.count else { return nil }
        return calendar.date(byAdding: DateComponents(day: min(max(1, day), length) - 1, hour: 9), to: first)
    }

    /// Due months after `lastAutoMonth` whose due date has come, oldest first.
    /// The caller pays the ones not already paid and remembers the last month as handled, so a month
    /// you untick by hand isn't paid again.
    static func monthsToHandle(dueMonths: [String], dueDay: Int, lastAutoMonth: String?, now: Date,
                               calendar: Calendar = .current) -> [String] {
        dueMonths.sorted().filter { month in
            guard lastAutoMonth.map({ month > $0 }) ?? true,
                  let due = dueDate(month: month, day: dueDay, calendar: calendar) else { return false }
            return due <= now
        }
    }

    /// When you first give a bill a due day, months before this one are left as they are.
    static func startingLastAutoMonth(now: Date, calendar: Calendar = .current) -> String {
        let current = MonthKey.key(for: now, calendar: calendar)
        guard let first = MonthKey.firstDay(of: current, calendar: calendar),
              let previous = calendar.date(byAdding: .month, value: -1, to: first) else { return current }
        return MonthKey.key(for: previous, calendar: calendar)
    }

    /// "15th", "1st", "22nd"… in English; just the number in other languages.
    static func ordinal(_ day: Int, locale: Locale = AppLanguage.locale) -> String {
        guard locale.language.languageCode?.identifier == "en" else { return "\(day)" }
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        f.locale = locale
        return f.string(from: NSNumber(value: day)) ?? "\(day)"
    }
}
