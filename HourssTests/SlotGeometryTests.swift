import Testing
import Foundation
@testable import Hourss

/// Where a slot is allowed to sit.
///
/// These replaced a set that tested the clamp the drag used, which guarded one
/// of the five paths that could write a slot. The other four — a preset, the
/// sheet's own default, an hour tapped on Today, and the binding itself — wrote
/// straight out, so a slot could land on top of a logged session with nothing to
/// stop it and nothing left to warn about it. Everything goes through
/// `SlotGeometry` now, so these are the tests that hold the guarantee up.
@Suite("Where a slot may sit")
struct SlotGeometryTests {

    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
    private var night: Date { day.addingTimeInterval(23 * 3600) }
    /// Midnight to eleven at night, which is what the sheet's window looks like
    /// for somebody logging in the evening.
    private func window(to end: Date? = nil) -> DateInterval {
        DateInterval(start: day, end: end ?? night)
    }

    private func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3600) }
    private func span(_ from: Double, _ to: Double) -> DateInterval {
        DateInterval(start: at(from), end: at(to))
    }

    private func gap(_ moment: Double, logged: [DateInterval], now: Date? = nil) -> DateInterval? {
        SlotGeometry.gap(containing: at(moment), in: window(to: now), logged: logged)
    }

    private func place(_ hours: Double, around moment: Double,
                       endingAt anchorEnd: Bool = true,
                       logged: [DateInterval] = [], now: Date? = nil) -> DateInterval? {
        SlotGeometry.place(length: hours * 3600, around: at(moment), endingAt: anchorEnd,
                           in: window(to: now), logged: logged)
    }

    private func resize(_ slot: DateInterval, _ edge: SlotGeometry.Edge, to moment: Double,
                        logged: [DateInterval] = [], now: Date? = nil) -> DateInterval? {
        SlotGeometry.resize(slot, edge: edge, to: at(moment), in: window(to: now), logged: logged)
    }

    // MARK: - Free room

    @Test("An empty day is one gap from midnight to now")
    func emptyDayIsOneGap() throws {
        let room = try #require(gap(9, logged: []))
        #expect(room == DateInterval(start: day, end: night))
    }

    @Test("A gap is bounded by whatever is logged either side of it")
    func gapIsBoundedBothWays() throws {
        let room = try #require(gap(12, logged: [span(9, 11), span(14, 15)]))
        #expect(room == span(11, 14))
    }

    @Test("There is no room inside something already logged")
    func occupiedHasNoRoom() {
        #expect(gap(10, logged: [span(9, 11)]) == nil)
    }

    @Test("There is no room in time that has not happened")
    func futureHasNoRoom() {
        #expect(gap(15, logged: [], now: at(11)) == nil)
    }

    // MARK: - Placing a whole slot

    /// The bug that was reported: a preset landing on top of a session.
    @Test("A preset cannot be placed on top of a logged session")
    func presetCannotOverlap() throws {
        // "The last hour", asked for at 12:00, with something running 11:15–12:00.
        let placed = try #require(place(1, around: 12, logged: [span(11.25, 12)], now: at(12)))
        #expect(placed.end <= at(11.25), Comment(rawValue: "\(placed) runs into the 11:15 session"))
    }

    @Test("A preset shortens itself to the room available")
    func presetShortensToFit() throws {
        // Two hours wanted, forty-five minutes free.
        let placed = try #require(place(2, around: 12, logged: [span(9, 11.25)], now: at(12)))
        #expect(placed == span(11.25, 12))
    }

    /// A button that visibly does nothing reads as broken, so a preset with no
    /// room where it was asked for takes the nearest room behind it instead.
    @Test("A preset with no room where asked falls back to the room before it")
    func presetFallsBack() throws {
        let placed = try #require(place(1, around: 12, logged: [span(11.75, 12)], now: at(12)))
        #expect(placed.end <= at(11.75), Comment(rawValue: "\(placed) runs into the 11:45 session"))
        #expect(placed.duration == 3600)
    }

    @Test("A preset with no room anywhere places nothing")
    func presetWithNoRoomAtAllIsRefused() {
        // The whole loggable day already spoken for.
        #expect(place(1, around: 12, logged: [span(0, 12)], now: at(12)) == nil)
    }

    @Test("A preset ends at the moment asked for when there is room")
    func presetEndsAtNow() throws {
        let placed = try #require(place(1, around: 12, now: at(12)))
        #expect(placed == span(11, 12))
    }

    /// Today's hour strip taps an *empty* hour, so the slot belongs inside it
    /// rather than ending at its start.
    @Test("An hour tapped on the day is filled forward")
    func tappedHourFillsForward() throws {
        let placed = try #require(place(1, around: 9, endingAt: false))
        #expect(placed == span(9, 10))
    }

    @Test("An hour tapped next to a session fills only the room before it")
    func tappedHourStopsAtTheNextSession() throws {
        let placed = try #require(place(1, around: 9, endingAt: false, logged: [span(9.5, 11)]))
        #expect(placed == span(9, 9.5))
    }

    // MARK: - Moving one end

    @Test("Dragging the start moves only the start")
    func resizeStartLeavesTheEnd() throws {
        let moved = try #require(resize(span(9, 11), .start, to: 10))
        #expect(moved == span(10, 11))
    }

    @Test("Dragging the end moves only the end")
    func resizeEndLeavesTheStart() throws {
        let moved = try #require(resize(span(9, 11), .end, to: 13))
        #expect(moved == span(9, 13))
    }

    /// The jump that made the first version unusable: dragging back across a
    /// session and having the whole selection reappear on its far side.
    @Test("An end dragged into a logged session stops at its edge")
    func resizeStopsAtABlock() throws {
        let moved = try #require(resize(span(9, 11), .end, to: 16, logged: [span(13, 14)]))
        #expect(moved == span(9, 13), Comment(rawValue: "\(moved) crossed the 13:00 session"))
    }

    @Test("A start dragged back into a logged session stops at its edge")
    func resizeBackStopsAtABlock() throws {
        let moved = try #require(resize(span(12, 14), .start, to: 8, logged: [span(9, 10)]))
        #expect(moved == span(10, 14))
    }

    @Test("An end cannot be dragged past now")
    func resizeStopsAtNow() throws {
        let moved = try #require(resize(span(9, 10), .end, to: 20, now: at(13)))
        #expect(moved == span(9, 13))
    }

    @Test("The two ends cannot cross")
    func endsCannotCross() throws {
        let pulled = try #require(resize(span(9, 11), .start, to: 14))
        #expect(pulled.start < pulled.end)
        #expect(pulled.duration >= SlotGeometry.step)

        let pushed = try #require(resize(span(9, 11), .end, to: 6))
        #expect(pushed.start < pushed.end)
        #expect(pushed.duration >= SlotGeometry.step)
    }

    @Test("A slot may sit exactly against a session at either end")
    func abuttingIsAllowed() throws {
        let forward = try #require(resize(span(9, 10), .end, to: 11, logged: [span(11, 12)]))
        #expect(forward == span(9, 11))

        let back = try #require(resize(span(13, 14), .start, to: 12, logged: [span(11, 12)]))
        #expect(back == span(12, 14))
    }

    // MARK: - Stepping

    @Test("A nudge moves one end by a quarter hour")
    func nudgeMovesAQuarterHour() throws {
        let later = try #require(SlotGeometry.nudge(span(9, 10), edge: .end, by: 1, in: window(), logged: []))
        #expect(later == span(9, 10.25))

        let earlier = try #require(SlotGeometry.nudge(span(9, 10), edge: .start, by: -1, in: window(), logged: []))
        #expect(earlier == span(8.75, 10))
    }

    @Test("A nudge into a session does nothing")
    func nudgeRespectsBlocks() {
        let moved = SlotGeometry.nudge(span(9, 10), edge: .start, by: -1,
                                       in: window(), logged: [span(8, 8.75)])
        #expect(moved == nil || moved!.start >= at(8.75))
    }

    // MARK: - The property

    /// Every operation, over every arrangement: whatever comes back overlaps
    /// nothing and is at least one step long.
    @Test("Nothing any path produces can overlap a logged session")
    func nothingEverOverlaps() {
        let logged = [span(0, 6.5), span(9, 10.5), span(13, 14), span(16, 16.25)]
        var rng = Statistics.Seeded(seed: 0x5107)

        func check(_ result: DateInterval?, _ what: String) {
            guard let result else { return }
            #expect(result.duration >= SlotGeometry.step, Comment(rawValue: "\(what) → \(result)"))
            #expect(result.end <= night, Comment(rawValue: "\(what) → \(result) runs past now"))
            for existing in logged {
                let overlaps = result.start < existing.end && existing.start < result.end
                #expect(!overlaps, Comment(rawValue: "\(what) → \(result) overlaps \(existing)"))
            }
        }

        for _ in 0..<600 {
            let a = Double(rng.next() % 96) / 4
            let b = Double(rng.next() % 96) / 4
            let length = Double(1 + rng.next() % 16) / 4

            check(place(length, around: a, logged: logged), "place \(length)h at \(a) ending there")
            check(place(length, around: a, endingAt: false, logged: logged),
                  "place \(length)h at \(a) starting there")

            // Resizing only makes sense from a slot that is itself legal.
            guard let base = place(length, around: a, logged: logged) else { continue }
            check(resize(base, .start, to: b, logged: logged), "resize start of \(base) to \(b)")
            check(resize(base, .end, to: b, logged: logged), "resize end of \(base) to \(b)")
        }
    }

    /// And the same property with the blocks actually in play, which the loop
    /// above deliberately does not do for `place` — so it is done here.
    @Test("Placing among logged sessions never overlaps one")
    func placingAmongBlocksNeverOverlaps() {
        let logged = [span(0, 6.5), span(9, 10.5), span(13, 14), span(16, 16.25)]
        var rng = Statistics.Seeded(seed: 0x9A07)

        for _ in 0..<600 {
            let moment = Double(rng.next() % 96) / 4
            let length = Double(1 + rng.next() % 16) / 4
            for anchorEnd in [true, false] {
                guard let result = place(length, around: moment, endingAt: anchorEnd, logged: logged)
                else { continue }
                #expect(result.duration >= SlotGeometry.step)
                for existing in logged {
                    let overlaps = result.start < existing.end && existing.start < result.end
                    #expect(!overlaps, Comment(rawValue:
                        "\(result) overlaps \(existing) — \(length)h at \(moment), anchorEnd \(anchorEnd)"))
                }
            }
        }
    }
}
