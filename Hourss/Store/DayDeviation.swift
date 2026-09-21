import Foundation

/// One fact about today, drawn from the person's own history.
///
/// This is deliberately the smallest statistical object in the app. It answers a
/// single question — "is one of today's settled readings far from this person's
/// own middle?" — and it answers it about **one day**, which is why it lives
/// outside the pattern engine rather than inside it. The engine's job is claims
/// about relationships, and those need effect sizes, day counts and evidence
/// floors before they may be spoken. A deviation is not a relationship. It is a
/// number next to the same number's recent history, and the only honest thing it
/// can support is a superlative about the person's own record.
///
/// Nothing here knows about sessions, ratings or HealthKit. Given a day and a
/// history it returns a `Standout` or it returns nothing, and it is the caller's
/// problem what to do with that.
enum DayDeviation {

    // MARK: - What may be compared at all

    /// The only metrics a same-day deviation may be computed from.
    ///
    /// **This allowlist is the correctness rule of the whole feature.** It is
    /// spelled out metric by metric rather than derived from `isCumulative`,
    /// because the property it actually encodes is "settled by the time anybody
    /// opens the app", and no existing flag means that.
    ///
    /// `HealthService` reads with `end: Date()`. Today's row for a cumulative
    /// metric is therefore a *partial* day: at two in the afternoon today's step
    /// count is half a day of walking, and comparing half a day against a year of
    /// whole ones would score it two sigma low. The card would then tell somebody
    /// they had walked unusually little, every afternoon, for the rest of their
    /// life — confidently, in their own numbers, and wrong. The seven cumulative
    /// metrics (steps, active energy, exercise, daylight, mindful, workout, and
    /// sleep-as-a-total) are all exposed to that.
    ///
    /// Sleep is the exception that proves the shape of the rule: it is cumulative
    /// too, but the night it totals finished this morning, so by the time anybody
    /// rates a session it is complete. HRV, resting heart rate and respiratory
    /// rate are all Apple-computed overnight values — one settled number per day
    /// that does not grow as the day goes on.
    ///
    /// `heartRate` is excluded for the separate, older reason recorded on
    /// `HealthMetric.isDailyContext`: a day's mean heart rate measures how much
    /// somebody walked and how often the watch sampled.
    static let eligibleMetrics: [HealthMetric] = [
        .sleepHours,
        .hrv,
        .restingHeartRate,
        .respiratoryRate,
    ]

    // MARK: - Floors

    /// Prior days a metric needs before any comparison is made.
    ///
    /// Chosen rather than borrowed. The two existing floors in the codebase are
    /// for other shapes: `HealthDigest.minimumDaysPerSide = 5` sizes each half of
    /// a *split*, so it is a floor on ten days total, and the four-day median
    /// floor in `InteractionCandidates` only has to make a median mean something.
    /// This is a third shape — one point against a distribution — and what it
    /// needs is enough days for a MAD to be a scale estimate rather than an
    /// accident. Fourteen is two full weeks, which is also the shortest window
    /// that contains both of somebody's day types; a ten-day window of pure
    /// weekdays would call their first lie-in an extreme.
    static let minimumHistoryDays = 14

    /// How far from the middle a value has to sit before it is worth a sentence.
    ///
    /// 1.5 robust sigma is roughly the most extreme day in a fortnight, which is
    /// the cadence the card is built for. Lower and it fires most days, which
    /// makes it wallpaper; higher and it fires monthly, which makes the first
    /// rating of most days do nothing again.
    static let minimumZ = 1.5

    /// How far back the superlative has to reach to be worth stating.
    ///
    /// "Your longest night in two days" is true and useless. A week is the
    /// shortest span that reads as a span.
    static let minimumSpanDays = 7

    /// The smallest spread the denominator is allowed to take, per metric.
    ///
    /// A robust sigma of nearly zero is not evidence of an extraordinary day, it
    /// is evidence of a metric that barely moves — a watch reporting the same
    /// resting heart rate for a fortnight, or a sleep schedule held to the
    /// minute. Dividing by it manufactures an enormous z from a trivial
    /// difference. Same clamping idiom as the movement curve's `referenceSpread`
    /// (`Physiology.swift:366`), but the numbers differ per metric because the
    /// units do: fifteen minutes of sleep, three milliseconds of HRV, a beat and
    /// a half per minute, a third of a breath per minute. Each is about the
    /// smallest difference in that metric a person could be said to have had.
    static func spreadFloor(for metric: HealthMetric) -> Double {
        switch metric {
        case .sleepHours: 0.25          // hours — fifteen minutes
        case .hrv: 3                    // ms
        case .restingHeartRate: 1.5     // bpm
        case .respiratoryRate: 0.3      // breaths per minute
        // Unreachable: the allowlist above is the only caller's source of
        // metrics. Present because the switch is exhaustive.
        default: 1
        }
    }

    // MARK: - The result

    /// One metric's day, and how far out it sits.
    struct Standout: Equatable {
        let metric: HealthMetric
        /// Today's value, in the metric's own unit.
        let value: Double
        /// Signed robust z. Positive is above the person's own median.
        let z: Double
        /// Calendar days back to the nearest day that was more extreme in the
        /// same direction. `nil` when no recorded day in the window was.
        let daysSinceMoreExtreme: Int?
        /// Days the comparison actually had — recorded prior days, not the span
        /// they were spread over.
        let historyDays: Int

        /// The span the superlative may claim, in days.
        ///
        /// When some earlier day was more extreme the answer is exact. When none
        /// was, the honest ceiling is how much history there is, and we count
        /// recorded days rather than the calendar span they cover: a year of
        /// history with half its days missing supports "in 180 days", not "in 365
        /// days". Understating is the right direction to be wrong in.
        var spanDays: Int { daysSinceMoreExtreme ?? historyDays }

        var isHigh: Bool { z > 0 }
    }

    // MARK: - The comparison

    /// The single most deviant eligible metric for `day`, or nothing.
    ///
    /// Returns nothing far more often than it returns something, and that is the
    /// intended behaviour: most days are ordinary, and a card that fires on an
    /// ordinary day has to invent a reason to exist.
    static func standout(
        on day: Date,
        history: [HealthMetric: [Date: Double]],
        calendar: Calendar = .current
    ) -> Standout? {
        let today = calendar.startOfDay(for: day)
        var best: Standout?

        // `eligibleMetrics` is an array, so this loop has a fixed order and does
        // not inherit a Dictionary's per-process key ordering. Every ranking in
        // this codebase has to be reproducible — a card that differs between two
        // launches on identical data is a bug nobody can reproduce.
        for metric in eligibleMetrics {
            guard let byDay = history[metric], let value = byDay[today] else { continue }
            guard let candidate = evaluate(metric: metric, value: value, today: today,
                                           byDay: byDay, calendar: calendar)
            else { continue }

            // Strict `>` so that on an exact tie the earlier metric in the
            // allowlist wins, which keeps the tie-break deterministic too.
            if abs(candidate.z) > abs(best?.z ?? 0) { best = candidate }
        }
        return best
    }

    private static func evaluate(
        metric: HealthMetric,
        value: Double,
        today: Date,
        byDay: [Date: Double],
        calendar: Calendar
    ) -> Standout? {
        // Days before today only. A day with no reading is simply not here — it
        // is never a zero. `ObservationBuilder.swift:34-41` states the rule and
        // this is the fourth place it is enforced: a missing night arriving as
        // 0.0 would read as "slept none" and drag the median down far enough to
        // make an ordinary night look like a record.
        var priors: [(day: Date, value: Double)] = []
        for (recorded, recordedValue) in byDay where recorded < today {
            priors.append((calendar.startOfDay(for: recorded), recordedValue))
        }
        // Sorted before anything reads it, newest first, so both the median and
        // the walk back to a more extreme day are order-independent.
        priors.sort { $0.day > $1.day }

        guard priors.count >= minimumHistoryDays else { return nil }

        let values = priors.map(\.value)
        guard let middle = Physiology.median(values),
              let deviation = Physiology.medianAbsoluteDeviation(values)
        else { return nil }

        // 1.4826 puts a MAD on the same scale as a standard deviation for normal
        // data, which is what makes the result readable as a z at all. The clamp
        // is what stops a metric that barely moves from manufacturing one.
        let spread = max(deviation * 1.4826, spreadFloor(for: metric))
        let z = (value - middle) / spread
        guard abs(z) >= minimumZ else { return nil }

        // How far back the same direction was last beaten. `>=` / `<=` so a day
        // that merely equalled today ends the run: today is then not the longest
        // night in that span, it is joint longest, and the superlative would be
        // overclaiming by one word.
        var daysSinceMoreExtreme: Int?
        for prior in priors where z > 0 ? prior.value >= value : prior.value <= value {
            daysSinceMoreExtreme = calendar.dateComponents([.day], from: prior.day, to: today).day
            break
        }

        let standout = Standout(
            metric: metric,
            value: value,
            z: z,
            daysSinceMoreExtreme: daysSinceMoreExtreme,
            historyDays: priors.count
        )
        guard standout.spanDays >= minimumSpanDays else { return nil }
        return standout
    }
}

// MARK: - Ranking across metrics
//
// Picking one standout means comparing a sleep-hours z against an HRV-
// milliseconds z, and **this is the genuinely uncertain part of the design**.
// The robust z is unit-free by construction, which is the only reason the
// comparison is expressible at all — but unit-free is not the same as
// comparable. The four distributions have different shapes: sleep is bounded and
// largely chosen, so a 2σ night is a real decision somebody made; HRV is noisy
// and right-skewed, so a 2σ reading is closer to a routine Tuesday plus a watch
// that sampled oddly. Strictly, a 2σ HRV day is less surprising than a 2σ sleep
// day, and ranking them as equals over-selects HRV.
//
// We rank on |z| with no weighting anyway, for one reason: any weighting would
// be invented. There is no measurement in this codebase that says how much to
// discount an HRV sigma, and a hand-tuned constant would be a prior about
// physiology dressed as arithmetic — the exact failure the caveats exist to
// prevent. The consequence is bounded: the worst case is that the card is about
// the wrong true thing, not that it says a false one. If it ever needs fixing,
// the fix is per-metric calibration from the person's own history (how often
// does *this* metric clear 1.5σ for *this* person), not a constant.
