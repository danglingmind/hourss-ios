import Foundation

/// Every question the engine knows how to ask about a person, as data.
///
/// The old engine spelled sixteen comparisons out as sixteen blocks of code, each
/// with its own idea of what counted as evidence, and each naming an activity —
/// "Deep work", "Admin" — that a given person may never have logged. The registry
/// is instead a *function of the observations*: the activity hypotheses come from
/// the activities that are actually there, the health hypotheses from the metrics
/// that are actually there. Adding a question is adding an array element, and
/// adding a person's tenth activity adds its hypothesis without anyone editing
/// anything.
///
/// Nothing here computes. A `Hypothesis` is two predicates, some copy and an id;
/// the arithmetic lives in `Statistics` and the ordering in `Engine`, neither of
/// which knows what it is testing.
enum HypothesisRegistry {

    /// The full set of questions worth asking of this data.
    ///
    /// Order is deterministic — buckets in declaration order, activities and
    /// metrics sorted — because the correction step ranks by p-value and needs a
    /// stable tiebreak, and because a feed that reshuffles itself between two runs
    /// on identical data would be its own kind of lie.
    static func hypotheses(for observations: [EngineObservation]) -> [Hypothesis] {
        timeWindows() + activities(in: observations) + durations()
            + [workdayContrast()] + healthAssociations(in: observations)
            + physiology(in: observations) + residualCalibration(in: observations)
    }

    // MARK: - Physiology

    /// One per activity, over the movement-adjusted heart-rate residual.
    ///
    /// The same machinery as every other question — the residual is a column, not
    /// a special case. What differs is what may be said about it. A residual has no
    /// good direction *the app knows*: `OutcomeDirection` answers that from this
    /// person's own calibration or not at all, because a heart rate running above
    /// what movement explains is not a verdict on anything. The phrasing below
    /// reports the number and the movement context and stops there, and it does so
    /// whether a calibration exists or not — what a direction licenses is acting on
    /// claims about the *sessions*, never a word about the body. Anything past that
    /// — intensity, stress, strain — is a claim about a person's inner state that
    /// no wrist sensor can support, and making it would change what this product
    /// legally is.
    ///
    /// These are only registered for activities that actually carry residuals.
    /// Most sessions have none: the window needs enough heart-rate samples, a
    /// clean lead-in, and a fitted curve. Registering a question nobody has data
    /// for would cost every other hypothesis power under the correction for
    /// nothing.
    private static func physiology(in observations: [EngineObservation]) -> [Hypothesis] {
        let scorable = observations.filter { $0.heartRateResidual != nil }
        guard scorable.count >= 12 else { return [] }

        let names = Set(scorable.map(\.activityName)).sorted()
        return names.compactMap { name -> Hypothesis? in
            let mine = scorable.filter { $0.activityName == name }
            guard mine.count >= 6, scorable.count - mine.count >= 6 else { return nil }
            return Hypothesis(
                id: "physiology.\(slug(name)).vs.rest.\(Outcome.heartRateResidual.rawValue)",
                type: .bodyContext,
                outcome: .heartRateResidual,
                focusLabel: name,
                baselineLabel: "Your other sessions",
                focus: { $0.activityName == name && $0.heartRateResidual != nil },
                baseline: { $0.activityName != name && $0.heartRateResidual != nil },
                phrase: { finding in
                    let bpm = abs(meanResidual(of: finding.focusSessionIds, in: observations))
                    let pace = meanCadence(of: finding.focusSessionIds, in: observations)
                    let higher = finding.comparison.delta > 0
                    return "During \(name.lowercased()), your heart rate has run about "
                        + String(format: "%.0f", bpm) + " bpm "
                        + (higher ? "above" : "below") + " your usual for those hours, "
                        + movementPhrase(pace) + "."
                },
                caveat: residualCaveat,
                experiment: nil
            )
        }
    }

    /// The limit that travels with every claim resting on a heart-rate residual.
    ///
    /// One string, read by the physiology family and by the calibration below.
    /// The calibration's outcome is a rating rather than a heart rate, but the
    /// thing it splits on is the residual, so it inherits the residual's limit —
    /// and inherits it verbatim rather than in a second wording. Two caveats about
    /// one number is two places for one of them to drift into naming a cause, and
    /// `ResidualCopyTests.caveatMatchesTheRegistry` already holds a third copy of
    /// this sentence to this one.
    static let residualCaveat =
        "Heart rate moves with more than effort — a warm room, caffeine, or talking will do it."

    // MARK: - Calibration

    /// The one question whose answer is which way round a raised heart rate is for
    /// this person.
    ///
    /// Named rather than spelled out at each use, because three other places have
    /// to recognise exactly this question: `OutcomeDirection.resolved` reads its
    /// direction, and `Recommendations` and `ExperimentDesign` both refuse to act
    /// on it. Stable, like every id here, because insight identity rides on it.
    static let residualCalibrationId = "residual.higher.vs.lower.\(Outcome.feeling.rawValue)"

    /// Which way round a raised heart rate is, for this person.
    ///
    /// **The inversion against `physiology(in:)` is the whole mechanism.** That
    /// family has the residual as the *outcome* and splits on activity; this has
    /// the residual as the *split* and feeling as the outcome. Same number,
    /// opposite role — and only this way round can answer "is a heart rate above my
    /// usual a good sign or a bad one for me", which is the question
    /// `Outcome.heartRateResidual` has no answer to and `OutcomeDirection` needs
    /// one for.
    ///
    /// Everything else mirrors `healthAssociations`: the split is the person's own
    /// median over rows carrying both halves of the comparison, the sides are their
    /// own higher and lower and nobody else's, and the phrasing is anchored on the
    /// higher side with the direction supplied by the evidence.
    ///
    /// Two things are deliberately *not* mirrored, both because a residual is per
    /// session where `dayHealth` is per day:
    ///
    /// - **The median is over sessions, not days.** A day has no residual; two
    ///   sessions on one afternoon have two of them. Collapsing them to a day
    ///   would throw away the only thing this question has that the daily splits
    ///   do not.
    /// - **A day can land on both sides**, and that is the strongest property of
    ///   the design rather than a flaw in it. `Statistics.compare` resamples whole
    ///   days, so a drawn day carries its sessions into both arms, and everything
    ///   that travels with a day — how much somebody slept, whether it was a
    ///   workday, what kind of week it was — is held constant *inside* the
    ///   comparison instead of being a confound the caveat has to apologise for.
    ///   `CalibrationTests.comparesWithinDays` asserts it, against the
    ///   health family as the control.
    private static func residualCalibration(in observations: [EngineObservation]) -> [Hypothesis] {
        // Rows that could contribute to the comparison at all: both the thing being
        // split on and the thing being measured. A median taken over sessions
        // nobody rated would split the data at a point no evidence sits on either
        // side of — the same reason `healthAssociations` filters before taking one.
        //
        // The obvious next thought — score the unrated sessions from their own
        // residual and feed those back as outcomes — is forbidden rather than
        // merely unhelpful. It would test a hypothesis on numbers the app invented.
        // The residual is already its own outcome in `physiology(in:)`; nobody
        // guesses a rating.
        let values = observations
            .filter { $0.feeling != nil }
            .compactMap(\.heartRateResidual)
            .sorted()

        // Four, the same floor `healthAssociations` uses: below that a median is a
        // coin toss between two numbers.
        //
        // The twelve-residual floor `physiology(in:)` carries is deliberately not
        // repeated here. It exists there to stop one hypothesis *per activity*
        // being registered for a family that mostly has no data, and the cost it
        // avoids is the power every other hypothesis loses under the correction.
        // This is a single hypothesis whose binding constraint is `minimumDays`:
        // six distinct rated days on each side of the median is already at least
        // twelve rated sessions spread over at least twelve days, so the second
        // guard would refuse nothing the engine does not already refuse.
        guard values.count >= 4 else { return [] }
        let median = values[values.count / 2]

        return [Hypothesis(
            id: residualCalibrationId,
            type: .bodyContext,
            outcome: .feeling,
            focusLabel: "Above your usual",
            baselineLabel: "Below your usual",
            // `.nan` on both sides, so a session with no residual lands on
            // neither: every comparison against nan is false. The same device
            // `healthAssociations` uses for a day with no value for the metric, and
            // what `sidesAreDisjoint` rests on.
            focus: { ($0.heartRateResidual ?? .nan) >= median },
            baseline: { ($0.heartRateResidual ?? .nan) < median },
            phrase: { finding in
                // Anchored on the higher side, exactly as the health associations
                // are, with `direction` supplying which way it went. Written the
                // other way round it would need an elliptical lower phrasing and
                // would invite reading the heart rate itself as the good or bad
                // thing, which is the one reading this claim must not support.
                "Sessions where your heart rate ran above your usual have felt "
                    + direction(finding) + " than your others."
            },
            caveat: residualCaveat,
            // No experiment, and this is not an omission. A test of this claim
            // would be a test of the heart rate itself, and nothing in this app may
            // ever suggest raising or lowering one. `ExperimentDesign.isEligible`
            // refuses this id outright for the same reason.
            experiment: nil
        )]
    }

    /// How much movement there was, in words. Descriptive only: the sentence has
    /// to let the reader draw their own conclusion, because the data supports the
    /// observation and not the explanation.
    private static func movementPhrase(_ cadence: Double) -> String {
        switch cadence {
        case ..<10: "with almost no movement to account for it"
        case ..<40: "with only light movement"
        case ..<80: "while moving about"
        default: "while walking at a fair pace"
        }
    }

    private static func meanResidual(of ids: [UUID], in observations: [EngineObservation]) -> Double {
        let values = observations.filter { ids.contains($0.sessionId) }.compactMap(\.heartRateResidual)
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func meanCadence(of ids: [UUID], in observations: [EngineObservation]) -> Double {
        let values = observations.filter { ids.contains($0.sessionId) }.compactMap(\.cadence)
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Timing

    /// One per bucket, each against the rest of the day rather than against a
    /// fixed counterpart. Comparing afternoon to morning would leave midday and
    /// evening out of the baseline for no reason other than that the old code
    /// happened to pick two hours and hardcode them.
    private static func timeWindows() -> [Hypothesis] {
        TimeBucket.allCases.map { bucket in
            Hypothesis(
                id: "time.\(bucket.rawValue).vs.rest.\(Outcome.feeling.rawValue)",
                type: .bestTimeWindow,
                outcome: .feeling,
                focusLabel: bucket.label,
                baselineLabel: "Rest of the day",
                focus: { $0.timeBucket == bucket },
                baseline: { $0.timeBucket != bucket },
                phrase: { finding in
                    "Your \(bucket.label.lowercased()) sessions have felt "
                        + direction(finding) + " than the rest of your day lately."
                },
                caveat: "Time of day travels with whatever you tend to schedule then.",
                experiment: "Try moving one \(bucket.label.lowercased()) block to a different hour this week and see whether it still reads the same."
            )
        }
    }

    // MARK: - Activities

    /// One per activity the person has actually logged, each against everything
    /// else they logged. Names come from the data, so a custom activity is a
    /// first-class question rather than something the engine cannot see.
    private static func activities(in observations: [EngineObservation]) -> [Hypothesis] {
        let names = Set(observations.map(\.activityName)).sorted()
        return names.map { name in
            Hypothesis(
                id: "activity.\(slug(name)).vs.rest.\(Outcome.feeling.rawValue)",
                type: .activityEnergizer,
                outcome: .feeling,
                focusLabel: name,
                baselineLabel: "Everything else",
                focus: { $0.activityName == name },
                baseline: { $0.activityName != name },
                phrase: { finding in
                    "Your time in \(name) has felt "
                        + direction(finding) + " than your other activities lately."
                },
                caveat: "What you do and when you do it are hard to pull apart.",
                experiment: nil
            )
        }
    }

    // MARK: - Duration

    private static func durations() -> [Hypothesis] {
        DurationBucket.allCases.map { bucket in
            Hypothesis(
                id: "duration.\(bucket.rawValue).vs.rest.\(Outcome.feeling.rawValue)",
                type: .durationSweetSpot,
                outcome: .feeling,
                focusLabel: bucket.label,
                baselineLabel: "Other lengths",
                focus: { $0.durationBucket == bucket },
                baseline: { $0.durationBucket != bucket },
                phrase: { finding in
                    "Your \(bucket.label.lowercased()) sessions have felt "
                        + direction(finding) + " than your other lengths lately."
                },
                caveat: "Longer sessions may simply be the harder work.",
                experiment: "Try one week where a block ends at the \(bucket.label.lowercased()) mark and see how it lands."
            )
        }
    }

    // MARK: - Workdays

    /// Non-workdays are the focus side because they are the smaller, more
    /// distinctive group; the direction of the claim still comes from the data.
    private static func workdayContrast() -> Hypothesis {
        Hypothesis(
            id: "workday.non.vs.work.\(Outcome.feeling.rawValue)",
            type: .workdayContrast,
            outcome: .feeling,
            focusLabel: "Non-workdays",
            baselineLabel: "Workdays",
            focus: { !$0.isWorkday },
            baseline: { $0.isWorkday },
            phrase: { finding in
                "Sessions on your non-workdays have felt "
                    + direction(finding) + " than the ones on workdays."
            },
            caveat: "Workdays and the rest are rarely the same kind of day.",
            experiment: nil
        )
    }

    // MARK: - Health

    /// One association per metric present in the data.
    ///
    /// The split is the person's own median for that metric, over the days that
    /// carry both a value and a rating — so the two sides are their own higher and
    /// lower days and nobody else's. Never a population, never a verdict on the
    /// metric, and the phrasing sits on the day rather than on the person.
    private static func healthAssociations(in observations: [EngineObservation]) -> [Hypothesis] {
        HealthMetric.allCases.filter(\.isDailyContext).compactMap { metric -> Hypothesis? in
            // Days that could contribute to the comparison at all. Taking the
            // median over days without a rating would split the data at a point
            // no evidence sits on either side of.
            var valueByDay: [Date: Double] = [:]
            for observation in observations where observation.feeling != nil {
                if let value = observation.dayHealth[metric] { valueByDay[observation.day] = value }
            }
            let values = valueByDay.values.sorted()
            guard values.count >= 4 else { return nil }
            let median = values[values.count / 2]

            return Hypothesis(
                id: "health.\(metric.rawValue).higher.vs.lower.\(Outcome.feeling.rawValue)",
                type: metric == .sleepHours ? .sleepContext : .bodyContext,
                outcome: .feeling,
                focusLabel: metric.highLabel,
                baselineLabel: metric.lowLabel,
                focus: { ($0.dayHealth[metric] ?? .nan) >= median },
                baseline: { ($0.dayHealth[metric] ?? .nan) < median },
                phrase: { finding in
                    // Always anchored on the metric's *higher* side, with the
                    // direction supplied by the evidence. Writing the sentence the
                    // other way round would need the elliptical lower phrasing
                    // ("when it ran lower") and invite reading the metric itself as
                    // the good or bad thing.
                    "On days \(metric.higherPhrase), your sessions have felt "
                        + direction(finding) + " than on your other days."
                },
                caveat: metric.caveat,
                experiment: nil
            )
        }
    }

    // MARK: - Copy

    /// How a difference is named, given which way it went.
    ///
    /// Direction comes from the finding rather than from the hypothesis, so a
    /// claim can never say "energizing" about data that went the other way. There
    /// is no size word here on purpose: "clearly" and "slightly" would be a second
    /// opinion about the same interval the confidence band already reports.
    private static func direction(_ finding: Finding) -> String {
        let higher = finding.comparison.delta > 0
        switch finding.hypothesis.outcome {
        case .feeling: return higher ? "more energizing" : "more draining"
        case .performance: return higher ? "stronger" : "weaker"
        // Undirected on purpose: a heart rate above what movement explains is not
        // "worse", and calling it that would be a medical claim.
        case .heartRateResidual: return higher ? "higher" : "lower"
        }
    }

    /// Id-safe form of a user-supplied activity name.
    ///
    /// Runs of anything that is not a letter or a digit collapse to a single
    /// hyphen, so "Personal / Rest" is `personal-rest` today and `personal-rest`
    /// after the next rename of anything else. Identity of saved insights rides on
    /// this being boring.
    static func slug(_ name: String) -> String {
        var out = ""
        var pendingSeparator = false
        for character in name.lowercased() {
            if character.isLetter || character.isNumber {
                if pendingSeparator && !out.isEmpty { out.append("-") }
                pendingSeparator = false
                out.append(character)
            } else {
                pendingSeparator = true
            }
        }
        return out.isEmpty ? "unnamed" : out
    }
}

// MARK: - Direction of a type

extension InsightType {
    /// The same comparison, read the other way round.
    ///
    /// A hypothesis has to declare its type before it is tested, but four of the
    /// types are a matched pair distinguished only by which way the difference
    /// went. The registry declares the positive pole and `Engine` swaps in the
    /// counterpart when the evidence points down, rather than the registry
    /// emitting both and having the correction step pay for two tests of one
    /// question.
    var oppositeDirection: InsightType? {
        switch self {
        case .bestTimeWindow: .drainingTimeWindow
        case .drainingTimeWindow: .bestTimeWindow
        case .activityEnergizer: .activityDrain
        case .activityDrain: .activityEnergizer
        default: nil
        }
    }
}
