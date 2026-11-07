import XCTest
import SwiftUI
@testable import DailyBudget

/// Category guess, note suggestions, the month-end recap and night colours.
final class EverydayEaseTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Phnom_Penh")!
        return c
    }()

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testCategoryGuessFollowsYourHabitAtThisTime() {
        let past: [QuickAdd.Past] = [
            .init(category: .transport, note: "Grab", cents: 100, date: at(2026, 11, 3, 8, 10)),
            .init(category: .transport, note: "Grab", cents: 100, date: at(2026, 11, 4, 8, 20)),
            .init(category: .coffee, note: "Coffee", cents: 125, date: at(2026, 11, 4, 15, 0)),
            .init(category: .bills, note: "Bank", cents: 20_000, date: at(2026, 11, 4, 8, 0)),
        ]
        XCTAssertEqual(QuickAdd.guessCategory(from: past, now: at(2026, 11, 6, 8, 45), calendar: cal), .transport)
        // Only one coffee in the afternoon: not enough, so the default (food) is used.
        XCTAssertEqual(QuickAdd.guessCategory(from: past, now: at(2026, 11, 6, 15, 30), calendar: cal), .food)
        XCTAssertEqual(QuickAdd.guessCategory(from: [], now: at(2026, 11, 6, 7, 0), calendar: cal), .coffee)
        XCTAssertEqual(QuickAdd.guessCategory(from: [], now: at(2026, 11, 6, 12, 0), calendar: cal), .food)
    }

    func testNoteSuggestionsMatchWhatYouTypeSameCategoryFirst() {
        let past: [QuickAdd.Past] = [
            .init(category: .food, note: "Rice and pork", cents: 150, date: at(2026, 11, 1, 12)),
            .init(category: .food, note: "Rice and pork", cents: 175, date: at(2026, 11, 3, 12)),
            .init(category: .shopping, note: "Rice cooker", cents: 2_500, date: at(2026, 11, 2, 12)),
            .init(category: .food, note: "Noodles", cents: 200, date: at(2026, 11, 2, 19)),
        ]
        let s = QuickAdd.noteSuggestions(from: past, typed: "ric", category: .food)
        XCTAssertEqual(s.map(\.note), ["Rice and pork", "Rice cooker"])
        XCTAssertEqual(s.first?.cents, 175)  // the latest price
        XCTAssertTrue(QuickAdd.noteSuggestions(from: past, typed: "", category: .food).isEmpty)
        XCTAssertTrue(QuickAdd.noteSuggestions(from: past, typed: "noodles", category: .food).isEmpty)  // already typed in full
    }

    func testMonthEndRecapOnThe1st() {
        var s = ReminderPlanner.Settings(); s.recapOn = true
        let calc = BudgetCalculator(entries: [.init(date: at(2026, 11, 5, 9), cents: 1_000, countsAsLiving: true)],
                                    livingMonthlyCents: 9_200, calendar: cal)
        let r = ReminderPlanner.plan(now: at(2026, 11, 7, 12), settings: s, calculator: calc, loggedToday: false,
                                     bills: [], planMonths: ["2026-11", "2026-12"], streakStart: at(2026, 11, 4, 0))
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].fireDate, at(2026, 12, 1, 9))
        XCTAssertEqual(r[0].title, "November in review")
        XCTAssertTrue(r[0].body.hasPrefix("You spent $10.00 of $92 everyday money and saved $82.00"))
        XCTAssertTrue(r[0].body.hasSuffix("26 of 27 days on budget."))  // Nov 4–30; the 5th went over
    }

    func testNightColoursAreLighter() {
        XCTAssertEqual(Color.lightened(0x000000, by: 0.5), 0x7F7F7F)
        XCTAssertEqual(Color.lightened(0xFFFFFF, by: 0.45), 0xFFFFFF)
        XCTAssertEqual(Color.lightened(0x2F5D4A, by: 0), 0x2F5D4A)
    }
}
