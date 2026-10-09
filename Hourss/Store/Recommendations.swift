import Foundation

/// Layer 4: what to believe about a thin group, what to lead with, and what to
/// suggest doing about it.
///
/// Three pieces, in the order they run.
///
/// **Shrinkage** fixes the arithmetic of small groups. A mean of five Tuesdays is
/// mostly noise, and the noisiest groups are the ones that produce the most
/// extreme numbers — so the group that looks most striking is usually the one
/// with the least behind it.
///
/// **Surprise** fixes the ordering. Ranking claims by effect size guarantees
/// leading with the largest true thing about somebody, which is nearly always the
/// thing they already knew. What earns attention is the claim they could not have
/// written down themselves.
///
/// **Recommendations** turn a surviving claim into one action. Nothing here
/// computes a new comparison: a recommendation is a claim that already cleared
/// layer 1's interval gate and layer 2's correction, with a sentence attached. A
/// suggestion resting on evidence weaker than a published insight would be the
/// engine's own guardrails routed around from the outside.

// MARK: - Empirical-Bayes shrinkage

/// Pulls each group's estimate toward the person's own grand mean, by how much
/// evidence stands behind it.
///
/// **The target is the person, never a population.** This technique is normally
/// described as borrowing strength across the members of a population, and the
/// standard framing would have "the grand mean" be an average over people. It is
/// not one here and must never become one. Every group in a call to this type is
/// one slice of *one person's* history, and the mean they are pulled toward is
/// that person's own centre of gravity across their own slices. Nothing in Hourss
/// compares a person to anybody else, and this is the one place in the codebase
/// where the textbook version of the method would quietly introduce it.
enum Shrinkage {

    /// One slice of a person's history, reduced to day-level means.
    ///
    /// Days rather than sessions, for the same reason the bootstrap resamples days:
    /// three sessions logged on one afternoon are one afternoon's worth of
    /// evidence, and letting them count as three would make the shrinkage weight —
    /// which is a statement about how much is known — largest exactly for the
    /// person who logs in bursts.
    struct Group: Sendable {
        let key: String
        /// One value per distinct day this group has any evidence on.
        let dayMeans: [Double]
    }

    /// A group's estimate, before and after.
    struct Estimate: Sendable {
        let key: String
        /// The plain mean of the day means.
        let raw: Double
        /// The mean after shrinkage — what to expect from this group next time.
        let shrunk: Double
        let days: Int
        /// How much of the raw estimate survived, 0…1. Zero is total shrinkage to
        /// the grand mean; one leaves the estimate untouched.
        let weight: Double

        /// How far shrinkage moved the estimate. Signed toward the grand mean.
        var pull: Double { raw - shrunk }
    }

    /// Every group's estimate, plus the grand mean they were pulled toward.
    struct Result: Sendable {
        let grandMean: Double
        let estimates: [String: Estimate]
        /// Between-group variance, after subtracting the sampling noise that
        /// inflates it. Zero means this person's groups are indistinguishable.
        let between: Double
        /// Day-to-day variance within a group, pooled across groups.
        let within: Double

        subscript(key: String) -> Estimate? { estimates[key] }
    }

    /// Shrink every group toward the mean of the group means.
    ///
    /// ## How the two variance components are estimated
    ///
    /// This choice is the whole method — it is what sets the shrinkage strength,
    /// and any other pair of estimators would produce different numbers under the
    /// same name.
    ///
    /// - **Within (σ²)** is the pooled variance of *day means about their own
    ///   group mean*, on Σ(nᵍ − 1) degrees of freedom. It is the day-to-day
    ///   scatter a person has inside a single slice of their week, so a group of
    ///   n days carries standard error σ²/n. Pooled across groups rather than
    ///   estimated per group because a group of five days gives a variance
    ///   estimate barely more stable than the mean it is meant to qualify.
    ///
    /// - **Between (τ²)** is by method of moments: the observed variance of the
    ///   group means, minus the average sampling variance that is in there
    ///   whether or not the groups genuinely differ. Truncated at zero. That
    ///   truncation is not a technicality — when the spread across groups is no
    ///   wider than the noise inside them, τ² is zero, every weight is zero, and
    ///   every group collapses onto the grand mean. The estimator's own answer to
    ///   "these slices are not distinguishable" is to stop distinguishing them.
    ///
    /// A maximum-likelihood or REML fit of the same two components would be
    /// defensible and is more efficient with many groups. Method of moments is
    /// used because a person has four time buckets or eight activities, not four
    /// hundred, and because it is closed-form and inspectable — the reader of this
    /// file can check the arithmetic against the numbers on screen.
    static func shrink(_ groups: [Group]) -> Result {
        let usable = groups.filter { !$0.dayMeans.isEmpty }
        let means = usable.map { average($0.dayMeans) }

        // One group has nothing to be pulled toward but itself. Shrinking a lone
        // group toward its own mean is the identity, and pretending otherwise
        // would invent a target out of nothing.
        guard usable.count >= 2 else {
            let estimates = zip(usable, means).map { group, mean in
                Estimate(key: group.key, raw: mean, shrunk: mean,
                         days: group.dayMeans.count, weight: 1)
            }
            return Result(grandMean: means.first ?? 0,
                          estimates: Dictionary(uniqueKeysWithValues: estimates.map { ($0.key, $0) }),
                          between: 0, within: 0)
        }

        // Unweighted across groups on purpose. Weighting by day count would make
        // the target whatever the person does most, so their commonest activity
        // would become the thing every other activity is judged against — which is
        // a comparison nobody asked for and the wrong one to shrink toward.
        let grand = average(means)

        var betweenSS = 0.0
        var withinSS = 0.0
        var withinDF = 0
        for (group, mean) in zip(usable, means) {
            betweenSS += (mean - grand) * (mean - grand)
            for value in group.dayMeans { withinSS += (value - mean) * (value - mean) }
            withinDF += group.dayMeans.count - 1
        }
        let observedBetween = betweenSS / Double(usable.count - 1)

        // Every group has exactly one day, so nothing separates between-group
        // spread from within-group noise. Taking the observed spread as the noise
        // drives τ² to zero and shrinks everything fully, which is the honest
        // reading: one day per group is no evidence about group differences.
        let within = withinDF > 0 ? withinSS / Double(withinDF) : observedBetween

        let averageStandardError = usable
            .map { within / Double($0.dayMeans.count) }
            .reduce(0, +) / Double(usable.count)
        let between = max(0, observedBetween - averageStandardError)

        var estimates: [String: Estimate] = [:]
        for (group, mean) in zip(usable, means) {
            let standardError = within / Double(group.dayMeans.count)
            let total = between + standardError
            // Zero total variance means the day means are all identical and there
            // is nothing to shrink; leaving the estimate alone is right.
            let weight = total > 0 ? between / total : 1
            estimates[group.key] = Estimate(
                key: group.key,
                raw: mean,
                shrunk: grand + weight * (mean - grand),
                days: group.dayMeans.count,
                weight: weight
            )
        }
        return Result(grandMean: grand, estimates: estimates,
                      between: between, within: within)
    }

    /// Day-level groups over a set of observations.
    ///
    /// A row whose key is nil belongs to no group and is dropped: a partition is
    /// allowed to leave rows out, but never to place one in two groups.
    static func groups(
        in observations: [EngineObservation],
        outcome: Outcome = .feeling,
        by key: (EngineObservation) -> String?
    ) -> [Group] {
        var byKeyAndDay: [String: [Date: [Double]]] = [:]
        for observation in observations {
            guard let key = key(observation), let value = observation.value(of: outcome) else { continue }
            byKeyAndDay[key, default: [:]][observation.day, default: []].append(value)
        }
        // Sorted by day so the array is identical between two runs on the same
        // history; the arithmetic below is order-independent, but a value a test
        // can print and compare should not be.
        return byKeyAndDay
            .map { key, byDay in
                Group(key: key, dayMeans: byDay.sorted { $0.key < $1.key }.map { average($0.value) })
            }
            .sorted { $0.key < $1.key }
    }

    private static func average(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - Surprise

/// How much a claim tells somebody they did not already know.
///
/// The onboarding proof beat ranks by normalised effect size, and it reads as
/// accurate and flat: the largest true thing about a person is almost always the
/// thing they would have said themselves. "You sleep less on weekdays" wins on
/// magnitude every time; "your resting heart rate has come down three beats since
/// spring" loses on magnitude every time, and is the one worth reading.
///
/// So the ranking here is over information rather than size. Surprise is measured
/// in bits — `−log₂` of how ordinary the pattern is, in the direction it actually
/// went — which gives the two properties the ordering needs and one it gets for
/// free:
///
/// - an ordinary pattern scores near zero however large it is;
/// - a pattern that runs *against* the ordinary direction scores an order of
///   magnitude higher, because it is the same prior read from the other side;
/// - the scale is additive in the way evidence is, so multiplying by a modifier is
///   the same as adding a fixed number of bits.
enum Surprise {

    /// What a claim is about, stripped of how well evidenced it is.
    struct Pattern: Equatable, Sendable {
        enum Family: String, Sendable {
            case timeOfDay, duration, activity, workday, bodyAssociation, physiology, unknown
        }
        let family: Family
        /// The slice being claimed about — a bucket's raw value, an activity's
        /// slug, a metric's raw value.
        let subject: String
        /// Whether the focus side scored above the baseline.
        let raised: Bool

        var key: String { "\(family.rawValue).\(subject)" }
    }

    /// How ordinary a pattern is, and which way round.
    private struct Prior: Sendable {
        /// The direction the pattern ordinarily runs.
        let raised: Bool
        /// Roughly how widely it is believed, in that direction. One of `Belief`.
        let share: Double
    }

    /// Three levels, because two decimals were a lie about where these came from.
    ///
    /// **Every number in this table was hand-set from intuition.** They were
    /// plausible and they were not measured — the engine document says so in its own
    /// §10.7, and the table carried values like 0.68 and 0.66 beside each other as
    /// though the difference between them meant something. It did not. Nothing was
    /// ever measured that could distinguish them, and a reader coming to this file
    /// could not tell an invented precision from a recorded one.
    ///
    /// **Sourced or coarsened, and this is coarsened** — `PRD-HOURS.md` phase 5. The
    /// other branch would be a citation beside every row, and a citation that has not
    /// been checked is worse than an honest shrug: it moves the number from "somebody
    /// guessed" to "somebody measured" without anybody having measured. Where real
    /// sources are found later, a row may graduate to carrying one; until then three
    /// levels are what intuition can actually support, which is the engine document's
    /// own candidate for closing §10.7.
    ///
    /// **Collapsing creates ties on purpose.** Two rows that used to differ by two
    /// hundredths now score identically and are separated by specificity and evidence
    /// instead — the terms that rest on this person's own record. That is the right
    /// order of authority and it was obscured by a precision nobody had.
    ///
    /// The levels keep the old range's ends, so the ordering of the table as a whole
    /// is unchanged and only the invented distinctions inside it are gone.
    private enum Belief {
        /// Almost everybody believes it and there is a plain mechanism behind it.
        static let wide = 0.82
        /// Generally believed, and nothing about it is surprising.
        static let common = 0.68
        /// Believed by many and genuinely contested, or resting on evidence that is
        /// thin, lab-bound, or measuring something adjacent to what is claimed.
        static let leaning = 0.58
    }

    // MARK: The prior
    //
    // BOUNDARY — read before touching this table.
    //
    // These numbers encode what is *ordinarily* true of people. They exist to
    // decide what to say first and nothing else. The "No population comparison" rule forbids showing a person
    // any comparison against other people, so no value here, and no quantity
    // derived from one, may reach a statement, a caveat, an evidence line, or any
    // other string a person reads. It is legitimate to rank "your meetings are
    // energizing" above "your meetings drain you" because the second is ordinary.
    // It is forbidden to say the second is ordinary, or to hint at it with a word
    // like "unusually", "unlike most", or "rare". The person is told what is true
    // of them; the prior only decides which true thing comes first.
    //
    // The keys are `family.subject` from the hypothesis id grammar, which the
    // registry documents as stable — copy is not, so a label would be the wrong
    // key. An absent key means no expectation either way, which scores exactly one
    // bit: unusual activities are never penalised for being unusual, they are
    // merely not credited with violating an expectation nobody had.
    //
    // CHRONOTYPE — the caveat over every time-of-day row below, not only the
    // pairings.
    //
    // Between-person spread in when people are at their best is larger than the
    // average time-of-day effect itself. So a row saying afternoons read low is a
    // statement about a population whose two halves point opposite ways, and for any
    // one person it may well be backwards — a morning type and an evening type
    // differ by more than the row is worth. `PRD-VITALS.md` item 15 records the same
    // thing where the pairings were added.
    //
    // This is survivable only because of the boundary above: a prior chooses which
    // question gets asked, and the person's own fortnight answers it. A row that was
    // wrong about somebody costs them a question they did not need, which is cheap.
    // The same row quoted as a reason would cost them a wrong belief about
    // themselves, which is why it may never be quoted.
    //
    // It is also why no time-of-day row sits above `Belief.common`, and why the
    // pairings sit at `leaning`.
    private static let priors: [String: Prior] = [
        // Days off feel better than working days. As close to universal as
        // anything in this file.
        "workday.non": Prior(raised: true, share: Belief.wide),
        // The sleep association is the single most predictable finding the engine
        // can produce, and the one people quote at each other.
        "bodyAssociation.sleepHours": Prior(raised: true, share: Belief.wide),
        "bodyAssociation.steps": Prior(raised: true, share: Belief.common),
        "bodyAssociation.activeEnergy": Prior(raised: true, share: Belief.common),
        "bodyAssociation.exerciseMinutes": Prior(raised: true, share: Belief.common),
        "bodyAssociation.hrv": Prior(raised: true, share: Belief.common),
        "bodyAssociation.restingHeartRate": Prior(raised: false, share: Belief.common),
        "bodyAssociation.daylightMinutes": Prior(raised: true, share: Belief.leaning),
        // The post-lunch dip, and the morning it is measured against.
        "timeOfDay.afternoon": Prior(raised: false, share: Belief.common),
        "timeOfDay.morning": Prior(raised: true, share: Belief.common),
        "timeOfDay.evening": Prior(raised: false, share: Belief.leaning),
        // Long blocks tire people out. Short ones are a coin toss, and midday has
        // no folk expectation at all, so both are left absent.
        "duration.extended": Prior(raised: false, share: Belief.common),
        "duration.long": Prior(raised: false, share: Belief.leaning),
        // Priors over the default activity names only. A person's own activity is
        // absent from this table and therefore neutral — the table is a list of
        // things everybody already believes, not a list of things that count.
        "activity.meetings": Prior(raised: false, share: Belief.common),
        "activity.admin": Prior(raised: false, share: Belief.common),
        "activity.exercise": Prior(raised: true, share: Belief.common),
        "activity.personal-rest": Prior(raised: true, share: Belief.common),
        "activity.social": Prior(raised: true, share: Belief.leaning),

        // MARK: Pairings — one activity inside one band
        //
        // Deep work in a morning is not the expectation "mornings" and not the
        // expectation "deep work", and no row above can hold it: the rows are keyed
        // on one `family.subject` at a time. So a pairing is keyed on the two keys
        // it joins, in the id grammar's own words — `activity.deep-work` and
        // `timeOfDay.morning` become `activity.deep-work.timeOfDay.morning`. Nothing
        // else changes: the same `Prior(raised:share:)`, the same meaning for an
        // absent key, and no second mechanism.
        //
        // `expectedness(of:)` will never find one of these, because a `Pattern` has
        // exactly one family and a two-family key cannot be built from a finding.
        // That is correct rather than a gap. A pairing exists to order which
        // question gets *asked*; no claim about anybody is ever scored against it,
        // and `pairingsAreUnreachableFromAFinding` in `ExperimentPriorTests` pins
        // that the rows above still rank findings exactly as they did before these
        // were added.
        //
        // **These are the weakest rows in the table and their shares say so.**
        // Between-person chronotype spread is larger than the within-person
        // time-of-day effect, so for any one person the expectation may well point
        // the wrong way — which is the whole reason it may only choose a question
        // and never answer one. And the alertness work behind it is mostly small,
        // lab-based, and measuring reaction time rather than anything resembling
        // focused work. So these sit at the bottom of the range this table uses,
        // `Belief.leaning`, every one of them, against `wide` for days off: that is
        // the table saying out loud that it lists what everybody believes rather than
        // what has been shown. Two weeks of somebody's own ratings outranks all of
        // them.
        //
        // **Two deliberate absences, because this table cannot say what the belief
        // actually is.** Every row here means "the focus side reads above, or below,
        // this person's own baseline". The folk belief about admin in an afternoon is
        // not that admin reads well then — it is that the afternoon is the better
        // time *for admin*, a comparison inside one activity that a key of this shape
        // cannot express, so admin has no pairing at all. Evening exercise is absent
        // for the opposite reason: the belief is genuinely split, and absent is
        // precisely how this table spells "no expectation either way".
        //
        // Midday has no pairing for the same reason it has no row of its own. There
        // is no folk expectation about the middle of the day to record.
        "activity.deep-work.timeOfDay.morning": Prior(raised: true, share: Belief.leaning),
        "activity.deep-work.timeOfDay.afternoon": Prior(raised: false, share: Belief.leaning),
        // Believed, and barely — "I work better at night" is a thing a great many
        // people say about themselves. It used to sit two hundredths below its
        // neighbours to record that; it now ties with them, which is the honest
        // reading, since nothing was ever measured that could separate the two.
        "activity.deep-work.timeOfDay.evening": Prior(raised: false, share: Belief.leaning),
        // The one pairing that points where its own band does not: `timeOfDay.evening`
        // expects a session to read below, and the belief about creative work in an
        // evening runs the other way. A pairing that could only ever agree with its
        // band would not be worth a key.
        "activity.creative.timeOfDay.evening": Prior(raised: true, share: Belief.leaning),
        "activity.exercise.timeOfDay.morning": Prior(raised: true, share: Belief.leaning),
        // Not "meetings are draining" — that is the row above, and it stands on its
        // own. This is the narrower belief that a meeting in a morning costs the
        // hours people most want for something else.
        "activity.meetings.timeOfDay.morning": Prior(raised: false, share: Belief.leaning),
    ]

    /// What a finding is about, read off the hypothesis rather than the copy.
    ///
    /// The id grammar is `family.subject.vs.baseline.outcome`, and the registry
    /// keeps it boring on purpose because insight identity rides on it. Family
    /// names differ from id prefixes in two places, both because the id says where
    /// the split came from and this says what kind of claim it is: `health.` is a
    /// body association, and `physiology.` is the same body signal used as the
    /// outcome instead of the split.
    static func pattern(of finding: Finding) -> Pattern {
        let parts = finding.hypothesis.id.split(separator: ".").map(String.init)
        let raised = finding.comparison.delta > 0
        guard parts.count >= 2 else {
            return Pattern(family: .unknown, subject: finding.hypothesis.id, raised: raised)
        }
        let family: Pattern.Family
        switch parts[0] {
        case "time": family = .timeOfDay
        case "duration": family = .duration
        case "activity": family = .activity
        case "workday": family = .workday
        case "health": family = .bodyAssociation
        case "physiology": family = .physiology
        default: family = .unknown
        }
        return Pattern(family: family, subject: parts[1], raised: raised)
    }

    /// The share of people this pattern ordinarily holds for, in the direction it
    /// actually went. Never shown; see the boundary note above the table.
    static func expectedness(of pattern: Pattern) -> Double {
        guard let prior = priors[pattern.key] else { return 0.5 }
        // The direction violation is not a separate term. A pattern that runs the
        // other way is the same prior read from its complement, which is why
        // someone who sleeps *less* at weekends outranks the ordinary case by the
        // ratio log(1/0.15) : log(1/0.85) rather than by a bonus somebody tuned.
        return pattern.raised == prior.raised ? prior.share : 1 - prior.share
    }

    /// Whether the table holds any expectation about a key, in either direction.
    ///
    /// **Presence only, and no number crosses this boundary.** A caller choosing
    /// between a pairing key and the plain band key behind it has to know which one
    /// the table has a row for, and needs nothing else to decide. Telling it only
    /// that is what keeps the boundary note above the table true by construction
    /// rather than by discipline.
    static func hasExpectation(of key: String) -> Bool { priors[key] != nil }

    /// Which of these keys people in general expect to read *above* a person's own
    /// baseline, most expected first.
    ///
    /// **This returns keys and never shares, which is the whole design of it.** The
    /// boundary note forbids a prior's number reaching any string a person reads,
    /// and the surest way to keep that true is a caller that cannot see a number to
    /// leak: the share orders this list and then stays inside this type. What the
    /// caller learns is which question is worth asking first, which is exactly what
    /// a prior is for and nothing it could print.
    ///
    /// A key with no row is dropped rather than ordered last. An absent key means no
    /// expectation either way, and there is nothing to ask on the strength of an
    /// expectation nobody has.
    ///
    /// Ties fall back to the key, so the order never depends on dictionary
    /// iteration — the same rule `ranked` follows for the same reason.
    static func expectedRaised(among candidates: [String]) -> [String] {
        candidates
            .compactMap { key -> (key: String, share: Double)? in
                guard let prior = priors[key], prior.raised else { return nil }
                return (key, prior.share)
            }
            .sorted { $0.share == $1.share ? $0.key < $1.key : $0.share > $1.share }
            .map(\.key)
    }

    /// The key for one activity inside one band, in the id grammar's own words.
    ///
    /// Built here rather than written out by a caller, because the grammar is the
    /// thing that makes a pairing findable: a key assembled a character differently
    /// somewhere else would not fail or warn, it would silently mean "no expectation
    /// either way" — the same failure `ExperimentStarters` takes its ids from the
    /// registry to avoid.
    ///
    /// - Parameter slug: `HypothesisRegistry.slug` of the activity name, which is
    ///   what the id grammar carries.
    static func pairKey(activity slug: String, band: TimeBucket) -> String {
        "activity.\(slug).timeOfDay.\(band.rawValue)"
    }

    /// How narrow the slice being claimed about is, 0…1.
    ///
    /// "Your Tuesdays" reads as something the app went and found. "Your weekdays"
    /// reads as an assumption it started from, because five sevenths of the week
    /// is not a discovery about anybody. Measured as the focus side's share of the
    /// two sides; anything at or above half the data scores zero.
    static func specificity(of finding: Finding) -> Double {
        let focus = Double(finding.comparison.focusCount)
        let total = focus + Double(finding.comparison.baselineCount)
        guard total > 0 else { return 0 }
        return max(0, 1 - min(focus / total, 0.5) / 0.5)
    }

    /// Surprise, in bits, modified by specificity and by how firmly the claim
    /// stands up.
    ///
    /// The evidence term is deliberately bounded to a factor of 1.6 across the
    /// whole visible confidence range, while the prior spans a factor of about
    /// twelve. So evidence quality orders two claims of the same kind — which is
    /// what it should do — and can never lift an obvious claim over a surprising
    /// one, which is the failure this ranking exists to remove.
    static func score(_ finding: Finding) -> Double {
        let bits = -log2(max(0.02, expectedness(of: pattern(of: finding))))
        // A specific slice is worth up to half a bit more than a half-the-data one.
        let specific = 1 + 0.5 * specificity(of: finding)
        let confidence = Double(Engine.confidence(finding.comparison))
        let evidence = 0.6 + 0.4 * min(1, max(0, (confidence - 50) / 45))
        return bits * specific * evidence
    }

    /// Most surprising first. Ties fall back to confidence and then to the
    /// hypothesis id, so the order never depends on dictionary iteration.
    static func ranked(_ findings: [Finding]) -> [Finding] {
        findings
            .map { (finding: $0, score: score($0), confidence: Engine.confidence($0.comparison)) }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
                return $0.finding.hypothesis.id < $1.finding.hypothesis.id
            }
            .map(\.finding)
    }
}

// MARK: - Direction

extension Finding {
    /// Which half of a matched pair this turned out to be.
    ///
    /// The same resolution `Engine` applies before publishing, duplicated here
    /// because it is private there and a recommendation has to agree with the card
    /// it cites. If either copy changes, both must.
    var publishedType: InsightType {
        guard comparison.delta < 0,
              higherIsBetter == true,
              let opposite = hypothesis.type.oppositeDirection else { return hypothesis.type }
        return opposite
    }
}

// MARK: - Recommendations

/// One thing to try, resting on one claim that already survived everything.
struct Recommendation: Identifiable, Sendable {
    /// The insight this rests on. Shared identity rather than a new one, so the
    /// card and the suggestion cannot drift apart or be saved separately.
    var id: UUID { insightId }
    let insightId: UUID
    /// Which stated priority this serves, and at what position in their list.
    let priority: Priority
    let priorityRank: Int
    /// The surviving claim, in the words the feed uses for it.
    let claim: String
    /// The suggestion. One thing, this week, phrased as an experiment.
    let action: String
    /// The claim's own limit, carried along — a suggestion without it would be the
    /// one place in the app a caveat could be dropped.
    let caveat: String
    let confidence: Int
    /// Shrunk day-level estimate for the group being recommended, and the person's
    /// own grand mean across that family of groups.
    let figure: Double
    let baselineFigure: Double
    let evidence: String
    let surprise: Double
}

enum Recommendations {

    /// Recommendations for one engine run, in the person's own order of priorities.
    ///
    /// Runs the same two steps the feed runs and then stops: no comparison is
    /// computed here that a published insight would not already rest on.
    static func build(for input: EngineInput, resamples: Int = Statistics.resamples) -> [Recommendation] {
        let findings = Engine.applyingCorrection(to: Engine.findings(for: input, resamples: resamples))
        return build(from: findings, input: input)
    }

    /// - Parameter findings: already corrected. Passing uncorrected findings would
    ///   silently promote claims the feed refused to make, so the reportability
    ///   gate below rejects anything whose correction has not been run.
    static func build(from findings: [Finding], input: EngineInput) -> [Recommendation] {
        // Nothing was said about what matters, so there is no "the group they care
        // about" to recommend a better time for. The feed still has its claims;
        // this layer adds nothing rather than picking a priority on their behalf.
        guard !input.priorities.isEmpty else { return [] }

        let survivors = findings.filter {
            $0.isReportable
                && Confidence.band(Engine.confidence($0.comparison)) != .internalOnly
                // An undirected outcome has no better side, so no action can be
                // derived from it. A heart-rate residual used to be undirected
                // always; now it is undirected until this person's own calibration
                // has confirmed, and `Finding.direction` is where that answer lives.
                // The measurement is still never a thing to move a meeting *for* —
                // what a direction buys is the right to act on claims about the
                // *sessions*, which is what `action(for:)` emits.
                && $0.higherIsBetter != nil
                // The calibration itself is not actionable and must not be
                // offered. The only change it could suggest is a change to a heart
                // rate, which this app does not suggest. It is excluded here rather
                // than left to `action(for:)` returning nil, because that nil comes
                // from a `HealthMetric(rawValue:)` lookup failing on the id's
                // subject — an accident that happens to be right, which is not the
                // same as a rule.
                && $0.hypothesis.id != HypothesisRegistry.residualCalibrationId
        }
        guard !survivors.isEmpty else { return [] }

        // The best hour of the day, if one survived on its own evidence. Used to
        // give an activity recommendation a *time* — the thing the product is
        // actually for — and simply absent when it did not survive.
        let bestWindow = Surprise.ranked(survivors.filter { $0.publishedType == .bestTimeWindow })
            .max { Engine.confidence($0.comparison) < Engine.confidence($1.comparison) }

        var out: [Recommendation] = []
        var used: Set<String> = []

        for (rank, priority) in input.priorities.enumerated() {
            let candidates = Surprise.ranked(survivors.filter {
                priority.insightTypes.contains($0.publishedType) && !used.contains($0.hypothesis.id)
            })
            // Most surprising candidate that has an action attached. Walking down
            // this list is not a weakening — every entry cleared the same gates —
            // it only skips claims there is nothing honest to suggest about.
            guard let chosen = candidates.first(where: { action(for: $0, bestWindow: bestWindow) != nil }),
                  let action = action(for: chosen, bestWindow: bestWindow) else { continue }

            used.insert(chosen.hypothesis.id)
            out.append(recommendation(from: chosen, action: action,
                                      priority: priority, rank: rank, input: input))
        }
        return out
    }

    /// The one to lead with. Nil is a real answer and the common one early on.
    static func headline(for input: EngineInput, resamples: Int = Statistics.resamples) -> Recommendation? {
        build(for: input, resamples: resamples).first
    }

    // MARK: Assembly

    private static func recommendation(
        from finding: Finding,
        action: String,
        priority: Priority,
        rank: Int,
        input: EngineInput
    ) -> Recommendation {
        let shrunk = estimate(for: finding, in: input.observations)
        return Recommendation(
            insightId: Engine.identity(of: finding.hypothesis.id),
            priority: priority,
            priorityRank: rank,
            claim: finding.hypothesis.phrase(finding),
            action: action,
            caveat: finding.hypothesis.caveat,
            confidence: Engine.confidence(finding.comparison),
            figure: shrunk.figure,
            baselineFigure: shrunk.grandMean,
            evidence: evidence(for: finding, shrunk: shrunk),
            surprise: Surprise.score(finding)
        )
    }

    private struct Figures {
        let figure: Double
        let grandMean: Double
        let days: Int
    }

    /// The number a recommendation shows, shrunk.
    ///
    /// Deliberately not the same number as the insight's evidence line, which is a
    /// plain mean. An evidence line is a description of what happened and should
    /// be the raw figure; a recommendation is a bet about the next block, and the
    /// shrunk estimate is the better guess at that — it is the mean of what this
    /// group's ratings are expected to do, not of what they did.
    private static func estimate(for finding: Finding, in observations: [EngineObservation]) -> Figures {
        let family = Surprise.pattern(of: finding)
        let groups = Shrinkage.groups(in: observations, outcome: finding.hypothesis.outcome,
                                      by: partition(for: finding, family: family))
        let result = Shrinkage.shrink(groups)
        let key = focusKey(for: finding, family: family)
        guard let estimate = result[key] else {
            return Figures(figure: result.grandMean, grandMean: result.grandMean, days: 0)
        }
        return Figures(figure: estimate.shrunk, grandMean: result.grandMean, days: estimate.days)
    }

    /// Which slices this finding's group is shrunk among.
    ///
    /// The natural family where there is one — four time buckets, four lengths,
    /// every activity — because shrinking a bucket toward the average bucket is
    /// what borrowing strength means here. Where the hypothesis is already a split
    /// in two, its own two sides are the family.
    private static func partition(
        for finding: Finding,
        family: Surprise.Pattern
    ) -> (EngineObservation) -> String? {
        switch family.family {
        case .timeOfDay: return { $0.timeBucket.rawValue }
        case .duration: return { $0.durationBucket.rawValue }
        case .activity, .physiology: return { HypothesisRegistry.slug($0.activityName) }
        case .workday, .bodyAssociation, .unknown:
            let hypothesis = finding.hypothesis
            return { hypothesis.focus($0) ? "focus" : (hypothesis.baseline($0) ? "baseline" : nil) }
        }
    }

    private static func focusKey(for finding: Finding, family: Surprise.Pattern) -> String {
        switch family.family {
        case .timeOfDay, .duration, .activity, .physiology: family.subject
        case .workday, .bodyAssociation, .unknown: "focus"
        }
    }

    private static func evidence(for finding: Finding, shrunk: Figures) -> String {
        String(
            format: "%@ settles at %.1f against your %.1f overall · %d days, %@",
            finding.hypothesis.focusLabel, shrunk.figure, shrunk.grandMean,
            shrunk.days, Engine.describe(windowDays: finding.windowDays)
        )
    }

    // MARK: Copy

    /// One thing to try, or nil when there is nothing honest to suggest.
    ///
    /// A hypothesis that already carries an `experiment` uses it: that string was
    /// written for exactly this claim, with this bucket's name in it, and a second
    /// sentence saying the same thing differently would be the kind of drift the
    /// engine is built to prevent. The rest are written here, where the priority
    /// and the surviving timing claim are both in scope.
    private static func action(for finding: Finding, bestWindow: Finding?) -> String? {
        let label = finding.hypothesis.focusLabel
        // The best hour only qualifies an activity suggestion when it is a
        // different claim; pairing a timing claim with itself says nothing.
        let window = bestWindow.flatMap {
            $0.hypothesis.id == finding.hypothesis.id ? nil : $0.hypothesis.focusLabel.lowercased()
        }

        // Voice, and the whole difference between the two tiers.
        //
        // An experiment proposes a test: "try moving one afternoon block this
        // week and see whether it still reads the same." A recommendation states
        // what has already held up and leaves the acting to the person. If one of
        // these strings ever says "try", it has become an experiment and the free
        // and paid tiers say the same thing in the same words.
        //
        // That is not hypothetical. This function used to open every string with
        // "Try" and close most of them with "this week", and one branch returned
        // the hypothesis's own experiment text verbatim — the paid feature
        // emitting the free one.
        //
        // No time box either. "This week" belongs to a test with an end; a
        // recommendation describes a pattern that held across the whole window.
        switch finding.publishedType {
        case .bestTimeWindow, .drainingTimeWindow, .durationSweetSpot:
            let when = label.lowercased()
            return finding.publishedType == .drainingTimeWindow
                ? "Your \(when) is where blocks have held up least."
                : "Your \(when) is where blocks have held up best."

        case .activityEnergizer:
            guard let window else { return "\(label) has held up best given a block of its own." }
            return "\(label) has held up best in your \(window)."

        case .activityDrain:
            guard let window else { return "\(label) has held up least where it currently sits." }
            return "\(label) has held up least in your \(window)."

        case .workdayContrast:
            return finding.comparison.delta > 0
                ? "Your days off are where things have held up best."
                : "Your workdays are where things have held up best."

        // A physiology claim, which a confirmed calibration has just made reachable.
        //
        // **The lever is the activity, not the heart rate.** Nothing here may
        // suggest raising or lowering a reading — the direction exists so claims
        // about *sessions* can be acted on, and the only thing this finding names
        // that somebody can move is which activity gets the block. So the sentence
        // is about the activity and says where it sits relative to their own better
        // sessions, which is what the calibration established and the only thing it
        // established.
        //
        // No verdict on the number in either direction: "read closest to" and "read
        // furthest from" are statements about where this activity falls among their
        // own sessions, not about the heart rate being good, bad, high or low.
        case _ where finding.hypothesis.outcome == .heartRateResidual:
            let favourable = (finding.comparison.delta > 0) == (finding.higherIsBetter == true)
            return favourable
                ? "\(label) has read closest to your better sessions."
                : "\(label) has read furthest from your better sessions."

        case .sleepContext, .bodyContext:
            // The claim is about which days go better, so the only thing it
            // supports is *when* to put a block. It cannot support telling anybody
            // to sleep more or move more, which would be advice the data does not
            // reach and the app is not allowed to give.
            //
            // The nil arm is no longer only a guard against a type with no metric.
            // A confirmed calibration admits `physiology.<activity>` findings past
            // the direction filter above for the first time, and their subject is
            // an activity slug rather than a metric, so they land here and return
            // nil. That is deliberate and it is where this phase stops: the
            // instruction voice for a residual claim would have to be written twice
            // — here and in `ExperimentCopy`, which is the one file in this app
            // allowed to say "try" — and two wordings of one instruction is the
            // drift that file exists to prevent. A directed physiology finding is
            // therefore reachable by this filter and still produces no sentence,
            // which is an honest nothing rather than a guessed something.
            guard let metric = HealthMetric(rawValue: Surprise.pattern(of: finding).subject) else { return nil }
            let better = finding.comparison.delta > 0 ? metric.higherPhrase : metric.lowerPhrase
            return "Your bigger blocks have held up best on days \(better)."

        // Nothing in the registry produces these, and inventing a suggestion for a
        // claim shape that has never been tested would be a promise about evidence
        // that does not exist.
        case .performanceFeelingSplit, .fragmentation, .emergingChange:
            return nil
        }
    }
}
