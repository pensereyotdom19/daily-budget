import Foundation

/// Works out which local notifications to schedule. Pure logic so it can be unit tested;
/// `ReminderScheduler` hands the result to iOS.
///
/// - Morning: the next morning says the exact limit. Later mornings can't know what you'll
///   spend before then, so they just invite you to open the app.
/// - Evening: skipped today if you already logged something; otherwise it tells you what's left.
/// - Bills: on the 1st of each month the unpaid bills due that month, and again on the 25th
///   for any still not ticked paid.
enum ReminderPlanner {
    struct Settings: Equatable {
        var morningOn = false
        var morningMinutes = 8 * 60
        var eveningOn = false
        var eveningMinutes = 20 * 60
        var billsOn = false
        static let billMinutes = 9 * 60
        var anyOn: Bool { morningOn || eveningOn || billsOn }
    }

    struct BillDue {
        var name: String
        var cents: Int
        var month: String
        var isPaid: Bool
    }

    enum Kind: String { case morning, evening, billsDue, billsUnpaid }

    struct Reminder: Equatable {
        var id: String
        var kind: Kind
        var fireDate: Date
        var title: String
        var body: String
    }

    static func plan(now: Date, settings: Settings, calculator: BudgetCalculator, loggedToday: Bool,
                     bills: [BillDue], planMonths: [String], days: Int = 7) -> [Reminder] {
        let cal = calculator.calendar
        let today = cal.startOfDay(for: now)
        var out: [Reminder] = []

        func at(_ day: Date, _ minutes: Int) -> Date? {
            cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
        }
        func dayID(_ d: Date) -> String {
            let c = cal.dateComponents([.year, .month, .day], from: d)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }

        for offset in 0..<days {
            guard let day = cal.date(byAdding: .day, value: offset, to: today),
                  planMonths.contains(MonthKey.key(for: day, calendar: cal)) else { continue }

            if settings.morningOn, let fire = at(day, settings.morningMinutes), fire > now {
                let isNext = !out.contains { $0.kind == .morning }
                let body = isNext
                    ? "Today you can spend \(Money.format(calculator.limitCents(on: fire), alwaysShowCents: true))."
                    : "Open Daily Budget to see today's limit."
                out.append(Reminder(id: "morning-\(dayID(day))", kind: .morning, fireDate: fire,
                                    title: "Good morning", body: body))
            }

            if settings.eveningOn, let fire = at(day, settings.eveningMinutes), fire > now,
               !(offset == 0 && loggedToday) {
                let body = offset == 0
                    ? "Nothing logged yet today. You still have \(Money.format(calculator.summary(on: now).leftCents, alwaysShowCents: true)) to spend."
                    : "Did you spend anything today? Add it before you forget."
                out.append(Reminder(id: "evening-\(dayID(day))", kind: .evening, fireDate: fire,
                                    title: "Log today's spending", body: body))
            }
        }

        if settings.billsOn {
            let current = MonthKey.key(for: now, calendar: cal)
            for month in planMonths.filter({ $0 >= current }).prefix(3) {
                let unpaid = bills.filter { $0.month == month && !$0.isPaid }
                guard !unpaid.isEmpty, let first = MonthKey.firstDay(of: month, calendar: cal) else { continue }
                let list = unpaid.map { "\($0.name) \(Money.format($0.cents))" }.joined(separator: ", ")
                let total = Money.format(unpaid.reduce(0) { $0 + $1.cents })
                let name = MonthKey.title(of: month, calendar: cal)
                if let fire = at(first, Settings.billMinutes), fire > now {
                    out.append(Reminder(id: "bills-due-\(month)", kind: .billsDue, fireDate: fire,
                                        title: "Bills due in \(name)", body: "\(list). Total \(total)."))
                }
                if let d25 = cal.date(byAdding: .day, value: 24, to: first),
                   let fire = at(d25, Settings.billMinutes), fire > now {
                    out.append(Reminder(id: "bills-unpaid-\(month)", kind: .billsUnpaid, fireDate: fire,
                                        title: "Bills not paid yet",
                                        body: "\(name): \(list). Tick them in Plan once paid."))
                }
            }
        }

        return out.sorted { $0.fireDate < $1.fireDate }
    }
}
