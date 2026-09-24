import Testing
import Foundation
@testable import Hourss

/// The arithmetic the log sheet does to place a slot on the grid.
///
/// Guards a failure that was invisible: the sheet read the wall clock twice and
/// subtracted the readings, so its idea of "now" landed on the quarter-hour grid
/// or a quarter hour below it depending on which microsecond each call happened
/// in. A preset then set a slot fifteen minutes off roughly half the time, and
/// tapping it again re-rolled — which looks like a flaky tap and is arithmetic.
@Suite("Grid arithmetic is stable")
struct SlotGridTests {

    private static let step: Double = 15
    private static let window: Double = 16 * 60

    private func nowMinutes(reading: Date, origin: Date) -> Double {
        let elapsed = reading.timeIntervalSince(origin) / 60
        return (elapsed / Self.step).rounded(.down) * Self.step
    }

    /// One reading, used for both ends. This is the fix.
    @Test("One reading of the clock always lands on the grid")
    func oneReadingIsStable() {
        for offset in 0..<2_000 {
            let reading = Date(timeIntervalSince1970: 1_750_000_000 + Double(offset) * 1e-6)
            let origin = reading.addingTimeInterval(-Self.window * 60)
            #expect(nowMinutes(reading: reading, origin: origin) == Self.window, Comment(rawValue:
                "offset \(offset) gave \(nowMinutes(reading: reading, origin: origin))"))
        }
    }

    /// Two readings, which is what the sheet used to do. Kept so the failure is
    /// documented rather than remembered: this is allowed to be unstable, which
    /// is exactly why nothing may be built on it.
    @Test("Two readings of the clock do not")
    func twoReadingsDrift() {
        var landedShort = false
        for offset in 1..<2_000 {
            let first = Date(timeIntervalSince1970: 1_750_000_000)
            let second = first.addingTimeInterval(-Double(offset) * 1e-6)
            let origin = first.addingTimeInterval(-Self.window * 60)
            if nowMinutes(reading: second, origin: origin) < Self.window { landedShort = true; break }
        }
        #expect(landedShort, "two readings never disagreed — the guard above is then testing nothing")
    }
}
