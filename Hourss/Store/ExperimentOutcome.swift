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

        /// Whether the result is worth a sentence about the change at all.
        var isReadable: Bool { verdict != .cannotTell }
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
        let dayMeans = byDay.values.map { $0.reduce(0, +) / Double($0.count) }
        return dayMeans.reduce(0, +) / Double(dayMeans.count)
    }
}
