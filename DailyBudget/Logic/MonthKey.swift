import Foundation

/// Helpers for month keys like "2026-11".
enum MonthKey {
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    static func components(of key: String) -> (year: Int, month: Int)? {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return (y, m)
    }

    static func firstDay(of key: String, calendar: Calendar = .current) -> Date? {
        guard let (y, m) = components(of: key) else { return nil }
        return calendar.date(from: DateComponents(year: y, month: m, day: 1))
    }

    /// `count` consecutive month keys starting at `start`.
    static func range(start: String, count: Int) -> [String] {
        guard let (y, m) = components(of: start) else { return [] }
        return (0..<count).map { i in
            let total = (y * 12 + (m - 1)) + i
            return String(format: "%04d-%02d", total / 12, total % 12 + 1)
        }
    }

    static func title(of key: String, calendar: Calendar = .current) -> String {
        guard let d = firstDay(of: key, calendar: calendar) else { return key }
        let f = DateFormatter()
        f.calendar = calendar
        f.dateFormat = "MMMM"
        return f.string(from: d)
    }
}

/// Formats cents as dollars: 132 -> "$1.32", 470000 -> "$4,700".
enum Money {
    static func format(_ cents: Int, alwaysShowCents: Bool = false) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        let whole = cents % 100 == 0 && !alwaysShowCents
        f.minimumFractionDigits = whole ? 0 : 2
        f.maximumFractionDigits = whole ? 0 : 2
        return f.string(from: NSNumber(value: Double(cents) / 100)) ?? "$0"
    }

    /// Parses text like "1.25" or "1,25" into cents. Returns nil for empty or invalid input.
    static func parse(_ text: String) -> Int? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0 else { return nil }
        return Int((value * 100).rounded())
    }
}
