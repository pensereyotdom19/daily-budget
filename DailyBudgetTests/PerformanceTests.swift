import XCTest
@testable import DailyBudget

/// The running-total index must give exactly the same numbers as adding entries up one by one.
final class PerformanceTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Phnom_Penh")!
        return c
    }()

    private func randomEntries(_ count: Int, seed: UInt64) -> [BudgetCalculator.Entry] {
        var rng = SplitMix(seed: seed)
        let start = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        return (0..<count).map { _ in
            BudgetCalculator.Entry(date: start.addingTimeInterval(Double(rng.next() % (330 * 86_400))),
                                   cents: Int(rng.next() % 2_000) + 1,
                                   countsAsLiving: rng.next() % 4 != 0)
        }
    }

    /// The old way: scan everything.
    private func naiveLimit(_ entries: [BudgetCalculator.Entry], on date: Date, living: Int) -> Int {
        let month = cal.dateInterval(of: .month, for: date)!
        let dayStart = cal.startOfDay(for: date)
        let before = entries.filter { $0.countsAsLiving && $0.date >= month.start && $0.date < dayStart }.reduce(0) { $0 + $1.cents }
        let daysLeft = cal.range(of: .day, in: .month, for: date)!.count - cal.component(.day, from: date) + 1
        return max(0, living - before) / max(1, daysLeft)
    }

    func testIndexMatchesScanningEveryEntry() {
        let entries = randomEntries(1_500, seed: 42)
        let calc = BudgetCalculator(entries: entries, livingMonthlyCents: 200_000, calendar: cal)
        var day = cal.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 9))!
        for _ in 0..<330 {
            let start = cal.startOfDay(for: day), end = cal.date(byAdding: .day, value: 1, to: start)!
            let spent = entries.filter { $0.countsAsLiving && $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.cents }
            XCTAssertEqual(calc.spentCents(on: day), spent)
            XCTAssertEqual(calc.limitCents(on: day), naiveLimit(entries, on: day, living: 200_000))
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
    }

    func testChangingEntriesRebuildsTheIndex() {
        let d = cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 12))!
        var calc = BudgetCalculator(entries: [.init(date: d, cents: 300, countsAsLiving: true)],
                                    livingMonthlyCents: 9_200, calendar: cal)
        let copy = calc
        XCTAssertEqual(calc.spentCents(on: d), 300)       // builds the index
        calc.entries.append(.init(date: d, cents: 200, countsAsLiving: true))
        XCTAssertEqual(calc.spentCents(on: d), 500)       // sees the new entry
        XCTAssertEqual(copy.spentCents(on: d), 300)       // the copy is unaffected
        XCTAssertEqual(calc.whatIf(spending: 100, on: d).monthLeftAfter, 9_200 - 600)
        XCTAssertEqual(calc.spentCents(on: d), 500)       // what-if doesn't leak into the original
    }

    func testStreakOverTwoYearsIsFast() {
        let entries = randomEntries(4_000, seed: 7)
        let calc = BudgetCalculator(entries: entries, livingMonthlyCents: 10_000_000, calendar: cal)
        let end = cal.date(from: DateComponents(year: 2026, month: 11, day: 25))!
        let since = cal.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let started = Date()
        _ = calc.streak(endingOn: end, since: since)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
    }
}

private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
