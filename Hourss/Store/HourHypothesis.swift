import Foundation

/// A question about one hour of the clock, which exists only as something to test.
///
/// **Why this is not in `HypothesisRegistry`, and must never be.** Every row the
/// registry mints is tested on every run and enters `m` in the correction, so each
/// one costs every other hypothesis power. An hour row would be minted for one
/// person's one offered hour and would tax everybody's claims to buy it — and it
/// could never pay that back, because the question it asks has no evidence on one
/// side until somebody has spent a fortnight creating it. So it is built on demand,
/// carried by the proposal, and rebuilt from its id when the experiment settles.
/// `Engine.findings` never sees it and `m` never counts it.
///
/// **Why an hour needs a row of its own at all.** `ExperimentHours` first carried
/// its hour's *band* row, because `ExperimentOutcome` counts adherence with
/// `hypothesis.focus` and a change asking for seven o'clock while the focus matched
/// the whole morning would let somebody logging at eleven clear adherence without
/// doing the thing. That was correct and it made the feature unreachable: anybody
/// with a record dense enough for `RatingShape` to read has every band measured
/// already, so the row the offer carried was always a question the engine had
/// answered. `PRD-HOURS.md` §10.3 records the whole of it. An hour-shaped focus
/// fixes both halves at once — adherence counts the hour, and the question is new.
///
/// **Rebuildable from its id, which most registry rows are not.** A row for an
/// activity needs the person's own activity names; this one needs arithmetic on an
/// observation's start time and nothing else. That is what lets `hypothesis(for:)`
/// reconstruct it at settling time without storing a predicate, and it is why the id
/// carries the hour rather than an index into something.
enum HourHypothesis {

    /// How far either side of the hour a session still counts as being at it.
    ///
    /// **Half an hour, and narrow on purpose.** The whole point is to separate the
    /// offered hour from the ones somebody already uses, and those are often the
    /// neighbours — `SyntheticCohort.interpolator` logs 06:00 and 08:00 and is
    /// offered 07:00. At a full hour either side both of their existing habits would
    /// count as adherence and they could clear a fortnight without changing anything,
    /// which is the same failure the band row had, one step smaller.
    ///
    /// It is also roughly how precisely anybody schedules: somebody asked for seven
    /// who starts at 07:20 did the thing, and somebody who starts at 07:50 did not.
    static let window: TimeInterval = 30 * 60

    /// The id grammar's own shape — `family.subject.vs.baseline.outcome`, with the
    /// hour zero-padded so the ids sort the way the clock does.
    static func id(hour: Int, outcome: Outcome = .feeling) -> String {
        String(format: "hour.%02d.vs.rest.%@", hour, outcome.rawValue)
    }

    /// The hour an id names, or nil if it names something else.
    ///
    /// Deliberately strict: anything that is not exactly this grammar is somebody
    /// else's id, and guessing at a near-miss would let an unrelated experiment
    /// settle against an hour nobody agreed to.
    static func hour(fromId id: String) -> Int? {
        let parts = id.split(separator: ".").map(String.init)
        guard parts.count == 5, parts[0] == "hour", parts[2] == "vs", parts[3] == "rest",
              parts[1].count == 2, let hour = Int(parts[1]), (0..<24).contains(hour)
        else { return nil }
        return hour
    }

    /// Build the question for one hour.
    static func make(hour: Int, outcome: Outcome = .feeling,
                     calendar: Calendar = .current) -> Hypothesis {
        Hypothesis(
            id: id(hour: hour, outcome: outcome),
            type: .bestTimeWindow,
            outcome: outcome,
            focusLabel: ExperimentCopy.clockHour(hour),
            baselineLabel: "Rest of the day",
            focus: { isNear(hour, $0, calendar: calendar) },
            // Everything that is not the focus, rather than a second window. A row
            // may match neither side and must not match both — the registry test
            // asserts that of every row and this one keeps the same property by
            // construction.
            baseline: { !isNear(hour, $0, calendar: calendar) },
            phrase: { finding in
                // Reachable only if something ever ran this through the feed, which
                // nothing does: an hour row is never registered, so `Engine.findings`
                // cannot produce a `Finding` for it and no insight can be built from
                // one. Written rather than left to a fatal error because a crash is a
                // worse answer than a plain sentence, and `Hypothesis` requires it.
                "Your sessions around \(ExperimentCopy.clockHour(hour)) "
                    + "scored \(finding.comparison.delta > 0 ? "above" : "below") your others."
            },
            caveat: "Time of day travels with whatever you tend to schedule then."
        )
    }

    /// Rebuild the question an id names, for settling an experiment whose row was
    /// never in the registry.
    static func rebuilt(from id: String, calendar: Calendar = .current) -> Hypothesis? {
        guard let hour = hour(fromId: id) else { return nil }
        // Only `feeling`, because that is the only outcome an hour is ever offered
        // for — `ExperimentHours` builds nothing else. Parsing the outcome back out
        // would invent support for a shape no caller can produce.
        return make(hour: hour, outcome: .feeling, calendar: calendar)
    }

    /// Whether a session started close enough to the hour to count as being at it.
    ///
    /// Measured to the minute from the hour's own start, and wrapped, so an hour of
    /// midnight is reachable from 23:30 as well as 00:30. The same wrap
    /// `RatingShape.kernel` and `SyntheticCohort.hourTaper` both keep, and for the
    /// same reason: a day that stops at a boundary is a day cut in half somewhere
    /// arbitrary.
    static func isNear(_ hour: Int, _ observation: EngineObservation,
                       calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: observation.startAt)
        let at = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        let centre = Double(hour * 60)
        let raw = abs(at - centre)
        return min(raw, 24 * 60 - raw) * 60 <= window
    }
}
