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
        var weeklyOn = false
        var expiryOn = false
        var subscriptionsOn = false
        static let billMinutes = 9 * 60
        static let weeklyMinutes = 19 * 60
        var anyOn: Bool { morningOn || eveningOn || billsOn || weeklyOn || expiryOn || subscriptionsOn }
    }

    struct BillDue {
        var name: String
        var cents: Int
        var month: String
        var isPaid: Bool
    }

    enum Kind: String { case morning, evening, billsDue, billsUnpaid, weekly, expiry, renewal }

    struct Renewal {
        var id: UUID
        var name: String
        var cents: Int
        var date: Date
    }

    struct Reminder: Equatable {
        var id: String
        var kind: Kind
        var fireDate: Date
        var title: String
        var body: String
    }

    static func plan(now: Date, settings: Settings, calculator: BudgetCalculator, loggedToday: Bool,
                     bills: [BillDue], planMonths: [String], days: Int = 7,
                     appExpiresAt: Date? = nil, streakStart: Date = .distantPast,
                     categoryTitle: (String) -> String = { $0 },
                     renewals: [Renewal] = []) -> [Reminder] {
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
                    ? String(localized: "Today you can spend \(Money.format(calculator.limitCents(on: fire), alwaysShowCents: true)).", bundle: AppLanguage.bundle)
                    : String(localized: "Open Daily Budget to see today's limit.", bundle: AppLanguage.bundle)
                out.append(Reminder(id: "morning-\(dayID(day))", kind: .morning, fireDate: fire,
                                    title: String(localized: "Good morning", bundle: AppLanguage.bundle), body: body))
            }

            if settings.eveningOn, let fire = at(day, settings.eveningMinutes), fire > now,
               !(offset == 0 && loggedToday) {
                let body = offset == 0
                    ? String(localized: "Nothing logged yet today. You still have \(Money.format(calculator.summary(on: now).leftCents, alwaysShowCents: true)) to spend.", bundle: AppLanguage.bundle)
                    : String(localized: "Did you spend anything today? Add it before you forget.", bundle: AppLanguage.bundle)
                out.append(Reminder(id: "evening-\(dayID(day))", kind: .evening, fireDate: fire,
                                    title: String(localized: "Log today's spending", bundle: AppLanguage.bundle), body: body))
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
                                        title: String(localized: "Bills due in \(name)", bundle: AppLanguage.bundle), body: String(localized: "\(list). Total \(total).", bundle: AppLanguage.bundle)))
                }
                if let d25 = cal.date(byAdding: .day, value: 24, to: first),
                   let fire = at(d25, Settings.billMinutes), fire > now {
                    out.append(Reminder(id: "bills-unpaid-\(month)", kind: .billsUnpaid, fireDate: fire,
                                        title: String(localized: "Bills not paid yet", bundle: AppLanguage.bundle),
                                        body: String(localized: "\(name): \(list). Tick them in Plan once paid.", bundle: AppLanguage.bundle)))
                }
            }
        }

        // Sunday 7 PM: the week so far (rescheduled every time the app opens or closes, so it stays current).
        if settings.weeklyOn {
            for offset in 0..<days {
                guard let day = cal.date(byAdding: .day, value: offset, to: today),
                      cal.component(.weekday, from: day) == 1,
                      let fire = at(day, Settings.weeklyMinutes), fire > now else { continue }
                let w = calculator.weekSummary(endingOn: day, now: now, since: streakStart)
                var body = String(localized: "\(Money.format(w.spentCents, alwaysShowCents: true)) spent on everyday things. \(w.daysOnBudget) of \(w.daysCounted) days on budget.", bundle: AppLanguage.bundle)
                if let top = w.topCategory {
                    body += " " + String(localized: "Most went to \(categoryTitle(top)).", bundle: AppLanguage.bundle)
                }
                out.append(Reminder(id: "weekly-\(dayID(day))", kind: .weekly, fireDate: fire,
                                    title: String(localized: "Your week", bundle: AppLanguage.bundle), body: body))
                break
            }
        }

        // Free Apple ID: the app stops opening 7 days after install. Warn the day before and that morning.
        if settings.expiryOn, let expiry = appExpiresAt, expiry > now {
            let time = expiry.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: AppLanguage.locale))
            let expiryDay = cal.startOfDay(for: expiry)
            if let dayBefore = cal.date(byAdding: .day, value: -1, to: expiryDay),
               let fire = at(dayBefore, Settings.billMinutes), fire > now {
                out.append(Reminder(id: "expiry-before", kind: .expiry, fireDate: fire,
                                    title: String(localized: "Reinstall Daily Budget soon", bundle: AppLanguage.bundle),
                                    body: String(localized: "It stops opening tomorrow at \(time). Run it from Xcode on your Mac to get 7 more days. Your data stays.", bundle: AppLanguage.bundle)))
            }
            if let fire = at(expiryDay, Settings.billMinutes), fire > now, fire < expiry {
                out.append(Reminder(id: "expiry-today", kind: .expiry, fireDate: fire,
                                    title: String(localized: "Daily Budget stops opening today", bundle: AppLanguage.bundle),
                                    body: String(localized: "At \(time). Run it from Xcode on your Mac to get 7 more days. Your data stays.", bundle: AppLanguage.bundle)))
            }
        }

        // Subscriptions: 9 AM two days before each renewal in the next 5 weeks, so there's time to cancel.
        if settings.subscriptionsOn {
            let horizon = cal.date(byAdding: .day, value: 35, to: now) ?? now
            for r in renewals where r.date > now && r.date < horizon {
                guard let twoBefore = cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: r.date)),
                      let fire = at(twoBefore, Settings.billMinutes), fire > now else { continue }
                let when = r.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().locale(AppLanguage.locale))
                out.append(Reminder(id: "renewal-\(r.id.uuidString)-\(dayID(r.date))", kind: .renewal, fireDate: fire,
                                    title: String(localized: "\(r.name) renews soon", bundle: AppLanguage.bundle),
                                    body: String(localized: "\(Money.format(r.cents, alwaysShowCents: true)) on \(when). Cancel before then if you don't need it.", bundle: AppLanguage.bundle)))
            }
        }

        return out.sorted { $0.fireDate < $1.fireDate }
    }
}
