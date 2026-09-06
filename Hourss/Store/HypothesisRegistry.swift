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
