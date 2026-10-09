import Foundation

/// A fortnight proposed from what somebody's own heart rate does across their own
/// day.
///
/// **The hole this fills.** Every other offer in this app is one of three things.
/// `ExperimentDesign` builds from a `Finding`, which is "this looked good, do more
/// of it" and needs a record that already varies. `ExperimentStarters` builds from a
/// stated priority and a Health reading about something else entirely, and never
/// looks at what somebody logs. `ExperimentGaps` builds from an absence. Asked what
/// evidence stood behind a suggestion, the honest answer was: not much, and none of
/// it about this person's own body.
///
/// `Physiology` has known the answer the whole time and never said it. A per-person
/// heart-rate baseline is fitted on `Cell { band, isWorkday }` from sixty days of
/// their own windows and used **only as a denominator** — every residual is measured
/// against it and nothing has ever read its shape. `Physiology.DayShape` is that
/// shape; this is what to do with it.
///
/// ## The chain, and the line it must not cross
///
/// > their vitals say the body sits differently at X
/// > → their calibration says that direction suits them
/// > → so: try the thing they care about at X, and find out
///
/// The second step is `OutcomeDirection`, which learns from this person's own
/// ratings whether a heart rate above their usual travels with better sessions **for
/// them**. Without it there is no direction at all, and "your heart rate is lower in
/// your mornings, work there" is an efficiency claim the app has no grounds for and
/// no licence to make. So the premise says only what was measured, with or without
/// one — see the calibration section below, which is the part of this file most
/// worth disagreeing with.
///
/// ## Why this cannot repeat the gap-filling mistake
///
/// Twice over, and both halves matter.
///
/// A cell earns a baseline from four windows of somebody's actual recorded day, so
/// **the shape only exists where they live.** Somebody who sleeps from four in the
/// afternoon has no evening cell, so no evening place, so this can never name an
/// evening to them. Gap-filling reasoned from absence and therefore pointed at
/// exactly the hours somebody does not have; this reasons from presence and
/// structurally cannot.
///
/// Then **the record is read as well, for two things it knows and the vitals do
/// not.** Which corners of their week they actually log in, which is a preference and
/// not a gate; and which band already holds most of their sessions, which is a
/// refusal. Both are in `ranked`, with the failure each one prevents written beside
/// it.
enum ExperimentVitals {

    // MARK: - Building

    /// One vitals-led proposal per priority that can take one, in the person's own
    /// order.
    ///
    /// - Parameter shape: from `Physiology.Analyzer.dayShape`. Nil and empty are the
    ///   same answer — nothing can be said about where their day differs — and both
    ///   produce no offers.
    /// - Parameter direction: this run's resolved calibration, which decides which
    ///   end of the curve is pointed at and never reaches a screen. **Every proposal
    ///   from one call is calibrated or none is**, because one direction is resolved
    ///   per engine run, so a caller ranking calibrated offers above uncalibrated ones
    ///   ranks the whole call on `direction.residualHigherIsBetter != nil` rather than
    ///   inspecting what came back. That is why no field was added to `Proposal` for
    ///   it: a field two sources must keep in agreement is a field they can disagree
    ///   about, which is the argument `Experiment.phase` already makes.
    /// - Parameter observations: the rows the engine is running on, read only for
    ///   where this person's sessions sit — see `ranked`. The rows rather than a
    ///   prepared summary, because deriving it here means the caller cannot hand over
    ///   something that disagrees with the record the fortnight will be measured in.
    ///   Empty is a real and common input: somebody on their first day has a watch
    ///   full of history and nothing logged, and nothing below treats that as a
    ///   reason to say nothing.
    /// - Parameter measured: hypothesis keys the engine already produced a finding
    ///   for. This stands down for those, for the reason `ExperimentStarters` does:
    ///   past that point the measured path owns the question, and a premise saying
    ///   nothing logged speaks to a band the engine has read six days of each side of
    ///   would be the app contradicting itself. It also stops the uglier case — asking
    ///   somebody for more of a band that currently reads *worse*, which no measured
    ///   proposal would ever do because `ExperimentDesign.isEligible` refuses it.
    /// - Parameter excluding: declines and everything already tested, as everywhere
    ///   else. Re-offering a question somebody has answered is the app not listening.
    /// - Parameter skipping: priorities a better offer already serves, so the list
    ///   never holds two offers for one focus area. `skipping` rather than a filtered
    ///   priority list, because `priorityRank` has to be the rank in what the person
    ///   actually ranked — reporting itself as their first priority because the two
    ///   above it were served elsewhere would be a lie about their own list.
    static func proposals(
        for priorities: [Priority],
        shape: Physiology.DayShape?,
        direction: OutcomeDirection = .uncalibrated,
        observations: [EngineObservation] = [],
        wake: Int? = nil,
        measured: Set<String> = [],
        excluding: Set<String> = [],
        skipping: Set<Priority> = []
    ) -> [ExperimentDesign.Proposal] {
        // Nothing was said about what matters, so there is no area to work on and
        // this layer picks none on somebody's behalf. The same guard
        // `ExperimentDesign.proposals` and `ExperimentStarters.build` open with.
        guard !priorities.isEmpty else { return [] }
        guard let shape, !shape.isEmpty else { return [] }

        let candidates = ranked(shape, direction: direction, observations: observations, wake: wake)
        guard !candidates.isEmpty else { return [] }

        var out: [ExperimentDesign.Proposal] = []
        var used = excluding.union(measured)

        for (rank, priority) in priorities.enumerated() where !skipping.contains(priority) {
            // Which priorities a time-of-day test can serve is `Priority.insightTypes`'
            // decision, not this file's — the same map `ExperimentDesign.proposals`,
            // `Recommendations.build` and `ExperimentStarters.shapes` all walk. Asked
            // as a question about the type rather than written as `case .focus`, so
            // that moving `bestTimeWindow` to another priority moves this with it
            // instead of leaving a hardcoded answer behind.
            guard priority.insightTypes.contains(.bestTimeWindow) else { continue }

            // Walking the list rather than taking the head and giving up, as
            // `Recommendations.build` and `ExperimentDesign.proposals` both do: a
            // place whose band has already been offered to an earlier priority, or
            // declined, or measured, should cost this priority its second-best place
            // rather than its only offer.
            for place in candidates {
                guard let hypothesis = timeWindow(place.band),
                      !used.contains(hypothesis.id) else { continue }
                used.insert(hypothesis.id)
                out.append(proposal(hypothesis, at: place, priority: priority, rank: rank))
                break
            }
        }
        return out
    }

    /// Real proposals, with vitals-led offers filling only the priorities they left
    /// empty.
    ///
    /// Mirrors `ExperimentStarters.completing` exactly, including why it exists: the
    /// precedence rule is enforced by the order the list comes back in rather than by
    /// a comparison somewhere, and a second assembly of the same list is a second
    /// chance to get that order wrong. Anything measured keeps its place at the
    /// front; these are appended behind all of them.
    static func completing(
        _ proposals: [ExperimentDesign.Proposal],
        priorities: [Priority],
        shape: Physiology.DayShape?,
        direction: OutcomeDirection = .uncalibrated,
        observations: [EngineObservation] = [],
        wake: Int? = nil,
        measured: Set<String> = [],
        excluding: Set<String> = []
    ) -> [ExperimentDesign.Proposal] {
        proposals + self.proposals(
            for: priorities,
            shape: shape,
            direction: direction,
            observations: observations,
            wake: wake,
            measured: measured,
            excluding: excluding.union(proposals.map(\.hypothesisId)),
            skipping: Set(proposals.map(\.priority))
        )
    }

    // MARK: - Choosing a place

    /// The places worth proposing, best first.
    ///
    /// ## What the calibration decides, and the join it rests on
    ///
    /// With a confirmed calibration this points at the end of somebody's curve the
    /// calibration says suits them: highest where a raised heart rate has gone with
    /// better-rated sessions, lowest where it has gone with worse. Without one there
    /// is no direction, so it points at whichever place sits furthest from the rest
    /// of the day in either direction and the copy says only what was measured.
    ///
    /// **The join between the two is weaker than the chain makes it sound, and it is
    /// worth being exact about why.** The calibration splits sessions on their
    /// *residual* — observed heart rate minus what this person's own cadence, band
    /// and day type predict — and a residual is measured against the band's own
    /// baseline by construction, so it is silent about where that baseline sits. A
    /// `Place` is the opposite quantity: a difference *between* baselines, with the
    /// residual divided out. Somebody for whom running above their usual goes with
    /// better sessions has not thereby been shown to do better in the band whose
    /// usual is highest; those are two different comparisons on the same person.
    ///
    /// So the direction is used as a *prior* and not as evidence: it chooses which
    /// true thing is offered first, exactly as `Surprise.expectedness` chooses which
    /// true thing is ranked first, and like a prior it never reaches a screen. That
    /// is also why `ExperimentCopy.vitalsPremise` is one sentence pair rather than
    /// two — printing the calibration's own claim beside the reading would invite the
    /// reader to make the join the data does not support, and the fortnight that
    /// follows is what was supposed to settle it.
    ///
    /// ## What the record adds
    ///
    /// **A refusal: never the band that already holds most of that day type.** This is
    /// filter 2 of `ExperimentDesign` arriving a layer early. The fortnight is settled
    /// against `time.<band>.vs.rest.feeling`, whose two sides are that band and the
    /// rest of the day, and adherence counts days gained on the *focus* side — so
    /// asking somebody who logs every single session at nine in the morning for one
    /// more morning session makes the heavy side heavier and the comparison no more
    /// possible than it was. `ExperimentOutcome` would return "cannot tell" in a
    /// fortnight, which is the app spending two weeks of somebody's attention on a
    /// question it already knew it could not answer.
    ///
    /// **A preference, not a gate: corners their record already occupies first.** The
    /// watch records a workday morning whether or not that morning is theirs to
    /// spend, and somebody who logs only on their days off has told us something about
    /// their weekday mornings the heart-rate feed cannot. So where there is evidence,
    /// it orders the list.
    ///
    /// It is deliberately not a gate, and that is a reversal worth recording. As a
    /// gate it refused everybody with an empty record — the person on their first day,
    /// who has sixty days of wrist data and nothing logged, and who is the whole
    /// reason this reads vitals rather than ratings. `PRD-VITALS.md` §7 says workdays
    /// are respected *for free*, because the cell already carries the distinction and
    /// `ExperimentCopy` names it in both sentences; the record is a second opinion on
    /// top of that, and a second opinion should reorder a list rather than empty it.
    ///
    /// **Waking is a gate, where the workday is only a preference.** The paragraph
    /// above records why the record had to stop emptying this list; an hour somebody
    /// is asleep for is a different case and does gate. "Put a block at 6am" to
    /// somebody who gets up at eight is not a suggestion about their day — it is an
    /// instruction to get up earlier wearing the costume of one, and `PRD-LOCKS.md`
    /// §6 refuses to ask anybody to do something they did not come here to do.
    ///
    /// It is safe as a gate only because `WakeShape.isAwake` is true whenever the
    /// waking time is unknown. Somebody whose sleep Health never recorded loses
    /// nothing, which is the same escape the workday preference needed and did not
    /// have. A place reported at band resolution carries no hour to judge and is
    /// always kept — a band spans hours on both sides of most people's waking, and
    /// refusing the whole of somebody's morning because its first hour is early
    /// would throw away the part of it they are up for.
    static func ranked(
        _ shape: Physiology.DayShape,
        direction: OutcomeDirection,
        observations: [EngineObservation],
        wake: Int? = nil
    ) -> [Physiology.DayShape.Place] {
        let dominant = dominantBands(in: observations)
        let allowed = shape.places
            .filter { dominant[$0.isWorkday] != $0.band }
            .filter { place in
                guard let hour = place.hour else { return true }
                return WakeShape.isAwake(at: hour, wake: wake)
            }

        let ends: [Physiology.DayShape.Place]
        switch direction.residualHigherIsBetter {
        case .some(true):
            ends = allowed.filter { !$0.isLower }.sorted { $0.difference > $1.difference }
        case .some(false):
            ends = allowed.filter(\.isLower).sorted { $0.difference < $1.difference }
        case .none:
            // Already furthest-from-the-rest first, and with a total order under
            // that — see `MovementCurve.dayShape`. Re-sorting here would be a second
            // opinion about the same ordering.
            ends = allowed
        }

        // A stable partition rather than a sort, so the direction's ordering survives
        // inside each half and an empty record changes nothing at all.
        let occupied = occupied(in: observations)
        return ends.filter { occupied.contains($0.cell) }
            + ends.filter { !occupied.contains($0.cell) }
    }

    /// Corners of the week this person's own sessions already occupy.
    ///
    /// Every logged session, not only the rated ones. What is being asked is whether
    /// their day has room for a session there, and a session they logged and never
    /// rated is still evidence that it did.
    static func occupied(in observations: [EngineObservation]) -> Set<Physiology.Cell> {
        Set(observations.map { Physiology.Cell(band: $0.timeBucket, isWorkday: $0.isWorkday) })
    }

    /// The band holding more than half of one day type's sessions, where one does.
    ///
    /// Per day type, because a fixed weekday routine says nothing about somebody's
    /// Saturdays and the hypothesis's two sides are the band against the rest of the
    /// day regardless of which kind of day it is.
    ///
    /// **More than half, rather than simply the largest.** The largest of four bands
    /// is whichever band somebody logs in slightly more often, which is true of
    /// everybody and is not the thing being guarded against. A band carrying a
    /// majority is a record with everything in one place, which is the shape that
    /// cannot produce a comparison however long the fortnight runs.
    ///
    /// Nothing logged means no majority and no refusal, which is the first-day case
    /// and is correct: a record with no sessions in it has not told us that any band
    /// is full.
    static func dominantBands(in observations: [EngineObservation]) -> [Bool: TimeBucket] {
        var out: [Bool: TimeBucket] = [:]
        for isWorkday in [true, false] {
            let rows = observations.filter { $0.isWorkday == isWorkday }
            guard !rows.isEmpty else { continue }
            let counts = Dictionary(grouping: rows, by: \.timeBucket).mapValues(\.count)
            // Count first, then the raw value, so a tie resolves the same way twice.
            guard let heaviest = counts.max(by: {
                ($0.value, $0.key.rawValue) < ($1.value, $1.key.rawValue)
            }), heaviest.value * 2 > rows.count else { continue }
            out[isWorkday] = heaviest.key
        }
        return out
    }

    // MARK: - The hypothesis

    /// The registry's own time-window question for a band.
    ///
    /// **Looked up rather than typed, for the reason `ExperimentStarters` gives at
    /// length.** The whole mechanism of an offer with nothing measured behind it is
    /// that its `hypothesisId` is the key `ExperimentOutcome` will look the predicate
    /// up by a fortnight later. An id written by hand here and drifting by one
    /// character from the registry's would not fail, break a test or log anything —
    /// it would settle every one of these as "cannot tell", silently, in two weeks,
    /// on somebody else's phone. The labels and the caveat come from the same row for
    /// the same reason: the proposal and the hypothesis it will be settled against
    /// have to name the two sides identically, or a settled card reads about a split
    /// the person was never offered.
    ///
    /// The four time windows are registered unconditionally, so this is never nil for
    /// a band. Kept optional rather than forced because a crash is a worse answer
    /// than no offer, and because `hypotheses(for:)` is free to stop registering them
    /// one day.
    ///
    /// Built per call rather than held in a `static let`, as `ExperimentStarters`
    /// does and for its reason: a `Hypothesis` carries two closures and so is not
    /// `Sendable`, and a shared mutable global of them does not compile under strict
    /// concurrency and should not.
    static func timeWindow(_ band: TimeBucket) -> Hypothesis? {
        HypothesisRegistry.hypotheses(for: []).first {
            $0.type == .bestTimeWindow && $0.focusLabel == band.label
        }
    }

    // MARK: - Assembly

    /// A place and its registry row, as something somebody can accept.
    ///
    /// **`Standing.starter`, and that is not modesty.** Nothing has been measured
    /// about how this band's *sessions* read — which is precisely what the fortnight
    /// is for — so there is no effect to quote and no day count to quote it across.
    /// The three evidence fields are zero for the reason `ExperimentStarters` gives:
    /// they exist so a lead can quote its shrunk estimate, and this has neither.
    /// What makes it better than a Health-seeded starter is not confidence but
    /// relevance — the premise is a measurement of this person's own body at the very
    /// hour being proposed, rather than a reading about something else.
    ///
    /// **`context` is nil**, which is a deliberate departure from the two other
    /// unmeasured sources. Both of them put their evidence in the quiet register
    /// precisely so it cannot sit directly beneath the change and read as the reason
    /// for it. Here the evidence *is* the premise: a reading about this hour is a
    /// legitimate reason to ask a question about this hour, and the sentence
    /// immediately after it says in plain words that nothing logged speaks to the
    /// answer yet. Splitting them would move the disclaimer away from the claim it
    /// qualifies, which is the one arrangement that would be worse than either.
    static func proposal(
        _ hypothesis: Hypothesis,
        at place: Physiology.DayShape.Place,
        priority: Priority,
        rank: Int
    ) -> ExperimentDesign.Proposal {
        ExperimentDesign.Proposal(
            hypothesisId: hypothesis.id,
            outcome: hypothesis.outcome,
            type: hypothesis.type,
            standing: .starter,
            focusLabel: hypothesis.focusLabel,
            baselineLabel: hypothesis.baselineLabel,
            premise: ExperimentCopy.vitalsPremise(place),
            context: nil,
            change: ExperimentCopy.vitalsChange(place),
            caveat: ExperimentCopy.vitalsCaveat(hypothesis.caveat),
            priority: priority,
            priorityRank: rank,
            evidenceDays: 0,
            figure: 0,
            baselineFigure: 0
        )
    }
}
