import Testing
import Foundation
@testable import Hourss

/// The arithmetic behind the Journal calendar.
///
/// Weekday alignment is where month grids go wrong, and it goes wrong quietly:
/// the grid still renders, the dates are still right, and every square sits one
/// column from where it belongs. Worth testing precisely because nothing about a
/// screenshot would catch it.
@Suite("Journal calendar")
struct CalendarTests {

    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// The offset the grid puts before the first of the month.
    private func leadingBlanks(for month: Date, in calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: month)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    @Test("A month starts at midnight on its first day")
    func startOfMonthIsTheFirst() {
        let calendar = calendar(firstWeekday: 2)
        let mid = date(2026, 9, 17, in: calendar)
        let start = calendar.startOfMonth(for: mid)
        #expect(calendar.component(.day, from: start) == 1)
        #expect(calendar.component(.month, from: start) == 9)
        #expect(calendar.component(.hour, from: start) == 0)
    }

    /// 1 September 2026 is a Tuesday. In a Monday-first week it sits one column in.
    @Test("The first of the month lands under its own weekday")
    func firstAlignsToItsWeekday() {
        let mondayFirst = calendar(firstWeekday: 2)
        let september = date(2026, 9, 1, in: mondayFirst)
        #expect(mondayFirst.component(.weekday, from: september) == 3, "1 Sept 2026 should be a Tuesday")
        #expect(leadingBlanks(for: september, in: mondayFirst) == 1)
    }

    @Test("The offset follows the person's own first day of the week")
    func offsetFollowsLocale() {
        let sundayFirst = calendar(firstWeekday: 1)
        let mondayFirst = calendar(firstWeekday: 2)
        let september = date(2026, 9, 1, in: sundayFirst)
        // The same Tuesday sits two columns in when the week starts on Sunday.
        #expect(leadingBlanks(for: september, in: sundayFirst) == 2)
        #expect(leadingBlanks(for: september, in: mondayFirst) == 1)
    }

    @Test("A month beginning on the first day of the week needs no blanks")
    func noBlanksWhenAligned() {
        // 1 June 2026 is a Monday.
        let mondayFirst = calendar(firstWeekday: 2)
        let june = date(2026, 6, 1, in: mondayFirst)
        #expect(mondayFirst.component(.weekday, from: june) == 2)
        #expect(leadingBlanks(for: june, in: mondayFirst) == 0)
    }

    @Test("Every month yields its own number of days, leap years included")
    func dayCounts() {
        let calendar = calendar(firstWeekday: 2)
        let cases: [(Int, Int, Int)] = [
            (2026, 9, 30), (2026, 1, 31), (2026, 2, 28),
            (2024, 2, 29),   // leap
            (2100, 2, 28),   // divisible by 100, not a leap year
        ]
        for (year, month, expected) in cases {
            let first = date(year, month, 1, in: calendar)
            let range = calendar.range(of: .day, in: .month, for: first)!
            #expect(range.count == expected, Comment(rawValue:
                    "\(year)-\(month) reported \(range.count) days, expected \(expected)"))
        }
    }

    @Test("Blanks plus days never exceed a six-week grid")
    func gridAlwaysFits() {
        // Thirty-one days starting on the last column is the worst case, and it
        // still has to fit six rows or the layout clips.
        for firstWeekday in 1...7 {
            let calendar = calendar(firstWeekday: firstWeekday)
            for month in 1...12 {
                let first = date(2026, month, 1, in: calendar)
                let cells = leadingBlanks(for: first, in: calendar)
                    + calendar.range(of: .day, in: .month, for: first)!.count
                #expect(cells <= 42, Comment(rawValue:
                        "2026-\(month) with firstWeekday \(firstWeekday) needs \(cells) cells"))
            }
        }
    }
}
