import Testing
import Foundation
@testable import Hourss

/// The no-overlap guarantee, which is now a clamp rather than a warning.
///
/// The sheet used to accept a slot that sat on top of an existing session and
/// print a note about it afterwards. That note is gone, so these are the tests
/// that stand between a drag and an overlapping session written to the record —
/// a failure here is not cosmetic.
@Suite("Slot picking cannot reach occupied time")
struct SlotPickerTests {

    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
    private var dayEnd: Date { day.addingTimeInterval(24 * 3600) }
    /// Late enough that "now" is not the thing doing the clamping in most cases.
    private var night: Date { day.addingTimeInterval(23 * 3600) }

    private func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3600) }
    private func span(_ from: Double, _ to: Double) -> DateInterval {
        DateInterval(start: at(from), end: at(to))
    }

    private func clamp(_ proposed: DateInterval,
                       logged: [DateInterval] = [],
                       now: Date? = nil) -> DateInterval? {
        SlotPicker.clamp(proposed, within: day, to: dayEnd,
                         logged: logged, now: now ?? night)
    }

    @Test("An empty day takes the slot as drawn")
    func emptyDayIsUntouched() throws {
        let result = try #require(clamp(span(9, 10.5)))
        #expect(result == span(9, 10.5))
    }

    /// The case the old warning existed for: a slot drawn across something that
    /// is already there.
    @Test("A slot growing into a logged session stops at its edge")
    func growthStopsAtTheNextSession() throws {
        let result = try #require(clamp(span(9, 14), logged: [span(11, 12)]))
        #expect(result == span(9, 11), Comment(rawValue:
            "ran to \(result.end) — through a session starting at 11"))
    }

    @Test("A slot starting inside a logged session moves nothing")
    func startingInsideRefuses() {
        #expect(clamp(span(11.5, 13), logged: [span(11, 12)]) == nil)
    }

    /// The boundary. A slot beginning exactly where a session ends is free time
    /// and must be allowed, or every session would be followed by a dead quarter
    /// hour nobody could log in.
    @Test("A slot may begin exactly where a session ended")
    func abuttingIsAllowed() throws {
        let result = try #require(clamp(span(12, 13), logged: [span(11, 12)]))
        #expect(result == span(12, 13))
    }

    @Test("A slot may end exactly where the next session begins")
    func abuttingForwardIsAllowed() throws {
        let result = try #require(clamp(span(10, 11), logged: [span(11, 12)]))
        #expect(result == span(10, 11))
    }

    /// The nearest session is what bounds it, not the first one in the array.
    @Test("The nearest session ahead is the one that stops it")
    func nearestBlockWins() throws {
        let result = try #require(clamp(span(8, 20), logged: [span(16, 17), span(10, 11)]))
        #expect(result == span(8, 10), Comment(rawValue: "stopped at \(result.end), not the 10:00 session"))
    }

    @Test("A slot is pushed off time already spent behind it")
    func startIsPushedPastTheLastSession() throws {
        // Drawn from 10:00, with something running until 10:30. The floor is the
        // end of that session rather than where the finger landed.
        let result = try #require(clamp(span(10, 13), logged: [span(9, 10)]))
        #expect(result.start >= at(10))
    }

    /// Nothing in the future has happened, so nothing there can be logged.
    @Test("Nothing can be logged past now")
    func nowIsACeiling() throws {
        let result = try #require(clamp(span(9, 20), now: at(11)))
        #expect(result == span(9, 11), Comment(rawValue: "ran to \(result.end), past a now of 11:00"))
    }

    @Test("A slot drawn entirely in the future is refused")
    func futureIsRefused() {
        #expect(clamp(span(14, 16), now: at(11)) == nil)
    }

    @Test("A slot cannot start before the day did")
    func dayIsAFloor() throws {
        let result = try #require(clamp(DateInterval(start: day.addingTimeInterval(-3600), end: at(2))))
        #expect(result.start == day)
    }

    /// The property the whole component rests on, over every arrangement rather
    /// than the handful above: whatever comes back, it overlaps nothing.
    @Test("Whatever survives the clamp overlaps nothing")
    func clampedSlotsNeverOverlap() {
        let logged = [span(1, 6), span(9, 10.5), span(13, 14), span(16, 16.5)]
        var rng = Statistics.Seeded(seed: 0x5107)

        for _ in 0..<400 {
            let from = Double(rng.next() % 96) / 4        // any quarter hour, 0–24
            let length = Double(1 + rng.next() % 32) / 4  // 15 min to 8 hours
            guard let result = clamp(DateInterval(start: at(from), duration: length * 3600),
                                     logged: logged)
            else { continue }

            #expect(result.duration > 0)
            for existing in logged {
                let overlaps = result.start < existing.end && existing.start < result.end
                #expect(!overlaps, Comment(rawValue:
                    "\(result) overlaps \(existing) — drawn from \(from) for \(length)h"))
            }
        }
    }
}
