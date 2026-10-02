import Foundation

/// What a window produced: how much of the change actually happened, and whether
/// it landed.
///
/// **Derived, never stored.** Adherence and the comparison are recomputed from the
/// sessions on every launch, like every other derived value in this app. The one
/// thing written down is `Experiment.Settlement`, and that is written down at the
/// instant the window closes and never recomputed — see its own documentation for
/// why a baseline drawn from a rolling window makes a settled figure unstable.
///
/// **The comparison is concurrent, not before-and-after.** Both sides are drawn
/// from inside the window: the focus group against the baseline group over the
/// same fortnight. The obvious alternative — the focus group now against the focus
/// group before — measures the change and the passage of time together, and a good
/// fortnight is indistinguishable from a successful experiment under it. A
/// concurrent control cannot be fooled that way, because a good fortnight lifts
/// both sides.
///
/// What that buys is weaker than a randomised trial and much stronger than mining:
/// the prediction was fixed before any of this data existed, and the data is
/// entirely out of sample. The honest claim is "this held up when you changed it on
/// purpose", which is what the copy says and is the most the design supports.
///
/// **A randomised window is read differently, and the difference is the point.**
/// When `Experiment.assignment` is set the two sides are no longer the hypothesis's
/// focus and baseline groups: they are the days the app drew and the days it did
/// not, and every rated session inside the window belongs to the arm its day was
/// assigned to whether or not the person managed the change that day. That is
/// intention-to-treat, and the alternative is the whole reason this phase exists.
/// Comparing the days the change actually happened on against the days it did not
/// would be conditioning on a choice the person made after the draw, which puts the
/// self-selection back in and leaves the randomisation buying nothing: the days
/// somebody manages a morning block on are not a random half of their month.
///
/// Compliance does not vanish from the reading, it moves: `adherenceDays` is the
/// assigned days the change happened on, `contaminationDays` is the unassigned days
/// it happened on anyway, and between them they decide whether there was a contrast
/// to read at all.
///
/// **No multiplicity correction, deliberately.** `Engine.applyingCorrection`
/// exists because sixty hypotheses are tested at once and the best of sixty looks
/// good by chance. One pre-registered hypothesis is not a search, so there is
/// nothing to correct for, and applying a sixty-candidate correction to a single
/// declared test would be arithmetic borrowed from a situation that is not this
/// one. `Experiment.predictsHigher` is what makes this legitimate rather than
/// convenient.
enum ExperimentOutcome {

    /// A window, read. Everything the settled card shows, plus what it took.
    struct Reading: Equatable {
        let verdict: Experiment.Verdict
        /// Distinct days inside the window carrying a rated session on the focus
        /// side. The count of the change actually having happened.
        let adherenceDays: Int
        /// Distinct days inside the window carrying a rated session on the other
        /// side. Without these there is nothing to read the focus against.
        let baselineDays: Int
        /// Mean of the day means on each side.
        ///
        /// Day means rather than session means, because the bootstrap resamples
        /// whole days and the figure shown has to be the figure that was tested.
        /// Three sessions on one good afternoon are one afternoon's worth of
        /// evidence, and a session mean would let them count as three.
        let focusFigure: Double
        let baselineFigure: Double
        /// Nil when the floors were not met, because nothing was compared.
        let comparison: Statistics.Comparison?

        /// Distinct days the change happened on when the app had not asked for it.
        ///
        /// Nil for a chosen window, where there is no such day: every day was the
        /// person's to use and none of them was withheld. Nil rather than zero,
        /// because zero is a real and different statement — somebody who kept off
        /// every unassigned day — and a card that could not tell the two apart would
        /// report perfect discipline for an experiment that never asked for any.
        let contaminationDays: Int?

        /// Whether the result is worth a sentence about the change at all.
        var isReadable: Bool { verdict != .cannotTell }

        /// Whether this window's days were drawn.
        var isRandomised: Bool { contaminationDays != nil }

        /// Unassigned days that carried a rated session and not the change.
        ///
        /// The only days a randomised window has to read its assigned days against,
        /// and therefore the number the floor is applied to. Nil for a chosen window.
        var contrastDays: Int? {
            contaminationDays.map { max(0, baselineDays - $0) }
        }

        /// Spelled out so `contaminationDays` can default to nil, which is what keeps
        /// every existing construction of a `Reading` — in this file, in the slot copy
        /// and in the suites — meaning what it meant before this phase.
        init(verdict: Experiment.Verdict,
             adherenceDays: Int,
             baselineDays: Int,
             focusFigure: Double,
             baselineFigure: Double,
             comparison: Statistics.Comparison?,
             contaminationDays: Int? = nil) {
            self.verdict = verdict
            self.adherenceDays = adherenceDays
            self.baselineDays = baselineDays
            self.focusFigure = focusFigure
            self.baselineFigure = baselineFigure
            self.comparison = comparison
            self.contaminationDays = contaminationDays
        }
    }

    /// Read a window.
    ///
    /// - Parameter hypothesis: looked up live from the registry by
    ///   `experiment.hypothesisId`. Nil is a real case rather than programmer
    ///   error — the activity a hypothesis named may have been deleted since the
    ///   person agreed to test it — and produces `cannotTell` rather than a
    ///   failure, because nothing about the change was disproved by the registry
    ///   losing a row.
    /// - Parameter observations: every row available, not only the window's. This
    ///   function does the window filtering itself so that a caller cannot
    ///   accidentally pre-filter to the focus side and turn the comparison into a
    ///   measurement of nothing.
    static func read(
        _ experiment: Experiment,
        hypothesis: Hypothesis?,
        observations: [EngineObservation],
        resamples: Int = 2000,
        calendar: Calendar = .current
    ) -> Reading {
        guard let hypothesis else { return unreadable() }

        // The one fork in this file. An experiment carries its kind in whether the
        // app drew its days, so there is nothing else to consult and no flag that
        // could disagree with the days themselves.
        if let assignment = experiment.assignment {
            return readAssigned(experiment, assignment: assignment, hypothesis: hypothesis,
                                observations: observations, resamples: resamples,
                                calendar: calendar)
        }

        let window = experiment.window(calendar: calendar)
        let outcome = experiment.outcome

        // Rated rows inside the window, split by the hypothesis's own predicates.
        // A row may match neither side; the registry test already asserts it
        // cannot match both.
        var focus: [Statistics.Observation] = []
        var baseline: [Statistics.Observation] = []
        for row in observations {
            guard window.contains(row.startAt), let value = row.value(of: outcome) else { continue }
            let point = Statistics.Observation(day: row.day, value: value)
            if hypothesis.focus(row) {
                focus.append(point)
            } else if hypothesis.baseline(row) {
                baseline.append(point)
            }
        }

        let focusDays = Set(focus.map(\.day)).count
        let baselineDays = Set(baseline.map(\.day)).count
        let focusFigure = meanOfDayMeans(focus)
        let baselineFigure = meanOfDayMeans(baseline)

        // Either floor unmet means there is nothing to read. Reported as
        // "cannot tell" with the counts intact, so the card can say what would
        // have been enough rather than only that it was not.
        guard focusDays >= Experiment.minimumDays, baselineDays >= Experiment.minimumDays else {
            return Reading(verdict: .cannotTell,
                           adherenceDays: focusDays, baselineDays: baselineDays,
                           focusFigure: focusFigure, baselineFigure: baselineFigure,
                           comparison: nil)
        }

        let comparison = Statistics.compare(focus: focus, baseline: baseline, resamples: resamples)

        // Two conditions, both required. The interval must exclude zero — the data
        // has to be inconsistent with no difference at all — and the difference
        // must run the way the person was told it would before the window opened.
        // Dropping the second would let an experiment "succeed" by coming out
        // backwards, which is the opposite of what was tested.
        let ranAsPredicted = experiment.predictsHigher ? comparison.delta > 0 : comparison.delta < 0
        let verdict: Experiment.Verdict =
            (!comparison.spansZero && ranAsPredicted) ? .heldUp : .didNotHoldUp

        return Reading(verdict: verdict,
                       adherenceDays: focusDays, baselineDays: baselineDays,
                       focusFigure: focusFigure, baselineFigure: baselineFigure,
                       comparison: comparison)
    }

    /// Read a window whose days the app drew.
    ///
    /// **The arms are days, not groups.** Every rated row inside the window joins
    /// the arm its day was assigned to. Nothing is filtered by the hypothesis's
    /// predicate, because the predicate describes what the person did and the whole
    /// value of a drawn assignment is that the sides were decided before they did
    /// anything. A day the change was asked for and did not happen on stays in the
    /// assigned arm and dilutes it, which is the honest cost of them not doing it and
    /// not a reason to quietly drop the day.
    ///
    /// **The predicate decides compliance instead**, on both sides: assigned days it
    /// matched are adherence, unassigned days it matched are contamination.
    ///
    /// **Why contamination gates the verdict, and why through the same floor.** An
    /// experiment where the change happened on all twenty-eight days has two arms
    /// that differ in nothing, and a difference measured between them is a difference
    /// between two indistinguishable halves of a month. That has to report that it
    /// cannot be read, exactly as too little adherence does, and for the same reason:
    /// the window did not produce the comparison it was for.
    ///
    /// The threshold is not a new number. The days that can serve as contrast are the
    /// unassigned days that carried a rating and *not* the change, and
    /// `Experiment.minimumDays` is already what this app requires of a side before it
    /// will read it. So the gate is six days of contrast, which is the existing floor
    /// applied to the only days that contrast. A contamination *percentage* was the
    /// alternative and was refused: it would have been a constant invented here, it
    /// would have passed windows with four clean days out of five, and it would have
    /// failed windows with twenty clean days out of forty.
    ///
    /// **Contaminated days stay in the comparison.** Only the gate excludes them.
    /// Dropping them from the unassigned arm would be a per-protocol analysis — the
    /// person chose which unassigned days to do it on anyway, and removing exactly
    /// those days reintroduces the selection the draw removed. They stay in, where
    /// they pull the two arms together and make the test harder to pass, which is the
    /// right direction for a bias to run.
    private static func readAssigned(
        _ experiment: Experiment,
        assignment: Experiment.Assignment,
        hypothesis: Hypothesis,
        observations: [EngineObservation],
        resamples: Int,
        calendar: Calendar
    ) -> Reading {
        let window = experiment.window(calendar: calendar)
        let outcome = experiment.outcome

        var assigned: [Statistics.Observation] = []
        var unassigned: [Statistics.Observation] = []
        var adherence: Set<Date> = []
        var contamination: Set<Date> = []

        for row in observations {
            // Two filters that should agree, and both applied rather than one
            // trusted. The half-open window decides membership; the day offset
            // decides the arm. A row that cleared one and not the other is dropped
            // instead of being put in an arm by default, because the default would
            // be unassigned and a silently mis-armed day is the one error here that
            // would never show up as anything but a slightly wrong number.
            guard window.contains(row.startAt), let value = row.value(of: outcome),
                  let offset = assignment.dayOffset(
                    of: row.startAt, startedAt: experiment.startedAt,
                    windowDays: experiment.windowDays, calendar: calendar)
            else { continue }

            let isAssignedDay = assignment.isAssigned(dayOffset: offset)
            let point = Statistics.Observation(day: row.day, value: value)
            if isAssignedDay { assigned.append(point) } else { unassigned.append(point) }

            // Compliance, which is about the change rather than about the rating.
            // Counted off rated rows only, like adherence always has been: an
            // unrated session contributes nothing to either arm, so counting it
            // would make the clean-day arithmetic below subtract days that were
            // never in the total.
            if hypothesis.focus(row) {
                if isAssignedDay { adherence.insert(row.day) } else { contamination.insert(row.day) }
            }
        }

        let unassignedDays = Set(unassigned.map(\.day)).count
        let adherenceDays = adherence.count
        let contaminationDays = contamination.count
        let contrastDays = max(0, unassignedDays - contaminationDays)
        let assignedFigure = meanOfDayMeans(assigned)
        let unassignedFigure = meanOfDayMeans(unassigned)

        func reading(_ verdict: Experiment.Verdict,
                     comparison: Statistics.Comparison?) -> Reading {
            Reading(verdict: verdict,
                    adherenceDays: adherenceDays, baselineDays: unassignedDays,
                    focusFigure: assignedFigure, baselineFigure: unassignedFigure,
                    comparison: comparison, contaminationDays: contaminationDays)
        }

        // Either floor unmet means there is nothing to read: the change did not
        // happen often enough when it was asked for, or it happened so often when it
        // was not that no contrast is left. The counts survive both ways, so the card
        // can say which of the two it was and what would have been enough.
        guard adherenceDays >= Experiment.minimumDays,
              contrastDays >= Experiment.minimumDays else {
            return reading(.cannotTell, comparison: nil)
        }

        let comparison = Statistics.compare(focus: assigned, baseline: unassigned,
                                            resamples: resamples)
        // The same two conditions as a chosen window, and the direction is read off
        // the same field fixed before the window opened. Randomising the days changes
        // what the arms are; it does not license deciding afterwards which way counted
        // as success.
        let ranAsPredicted = experiment.predictsHigher ? comparison.delta > 0 : comparison.delta < 0
        return reading((!comparison.spansZero && ranAsPredicted) ? .heldUp : .didNotHoldUp,
                       comparison: comparison)
    }

    /// Freeze a reading onto the experiment.
    ///
    /// Called once, when the window has closed. Separate from `read` so that the
    /// active card can read a window as often as it likes without ever writing
    /// anything — the figures become permanent at exactly one moment and by exactly
    /// one call.
    static func settle(
        _ experiment: Experiment,
        hypothesis: Hypothesis?,
        observations: [EngineObservation],
        now: Date,
        resamples: Int = 2000,
        calendar: Calendar = .current
    ) -> Experiment {
        guard experiment.phase == .active,
              experiment.hasClosed(at: now, calendar: calendar) else { return experiment }

        let reading = read(experiment, hypothesis: hypothesis, observations: observations,
                           resamples: resamples, calendar: calendar)
        var settled = experiment
        settled.settlement = Experiment.Settlement(
            verdict: reading.verdict,
            adherenceDays: reading.adherenceDays,
            baselineDays: reading.baselineDays,
            // Nil for a chosen window, which has no unasked days. Frozen with the
            // rest because the reason a verdict could not be read is part of the
            // result and the counts behind it move as the baseline window slides.
            contaminationDays: reading.contaminationDays,
            focusFigure: reading.focusFigure,
            baselineFigure: reading.baselineFigure,
            delta: reading.comparison?.delta ?? 0,
            intervalLow: reading.comparison?.low ?? -1,
            intervalHigh: reading.comparison?.high ?? 1,
            settledAt: now
        )
        return settled
    }

    // MARK: - Figures

    private static func unreadable() -> Reading {
        Reading(verdict: .cannotTell, adherenceDays: 0, baselineDays: 0,
                focusFigure: 0, baselineFigure: 0, comparison: nil)
    }

    /// Mean of the per-day means. Zero for an empty side, which is only ever read
    /// alongside a day count of zero and so cannot be mistaken for a rating.
    private static func meanOfDayMeans(_ points: [Statistics.Observation]) -> Double {
        guard !points.isEmpty else { return 0 }
        var byDay: [Date: [Double]] = [:]
        for point in points { byDay[point.day, default: []].append(point.value) }
        // Sorted before summing, which looks like pedantry about a mean and is not.
        // Dictionary iteration order is not stable between launches, floating-point
        // addition is not associative, and the two together move the last decimal of
        // a figure for a window that has not changed. A figure that moves between
        // launches cannot be shown to anybody as a result — the whole argument
        // `Settlement` makes about the baseline sliding, at a smaller scale.
        let dayMeans = byDay.keys.sorted().map { day -> Double in
            let values = byDay[day] ?? []
            return values.reduce(0, +) / Double(values.count)
        }
        return dayMeans.reduce(0, +) / Double(dayMeans.count)
    }
}
