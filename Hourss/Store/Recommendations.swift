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
        /// The share of people it ordinarily holds for, in that direction.
        let share: Double
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
    private static let priors: [String: Prior] = [
        // Days off feel better than working days. As close to universal as
        // anything in this file.
        "workday.non": Prior(raised: true, share: 0.85),
        // The sleep association is the single most predictable finding the engine
        // can produce, and the one people quote at each other.
        "bodyAssociation.sleepHours": Prior(raised: true, share: 0.82),
        "bodyAssociation.steps": Prior(raised: true, share: 0.70),
        "bodyAssociation.activeEnergy": Prior(raised: true, share: 0.68),
        "bodyAssociation.exerciseMinutes": Prior(raised: true, share: 0.68),
        "bodyAssociation.hrv": Prior(raised: true, share: 0.66),
        "bodyAssociation.restingHeartRate": Prior(raised: false, share: 0.68),
        "bodyAssociation.daylightMinutes": Prior(raised: true, share: 0.62),
        // The post-lunch dip, and the morning it is measured against.
        "timeOfDay.afternoon": Prior(raised: false, share: 0.70),
        "timeOfDay.morning": Prior(raised: true, share: 0.66),
        "timeOfDay.evening": Prior(raised: false, share: 0.60),
        // Long blocks tire people out. Short ones are a coin toss, and midday has
        // no folk expectation at all, so both are left absent.
        "duration.extended": Prior(raised: false, share: 0.74),
        "duration.long": Prior(raised: false, share: 0.60),
        // Priors over the default activity names only. A person's own activity is
        // absent from this table and therefore neutral — the table is a list of
        // things everybody already believes, not a list of things that count.
        "activity.meetings": Prior(raised: false, share: 0.78),
        "activity.admin": Prior(raised: false, share: 0.76),
        "activity.exercise": Prior(raised: true, share: 0.78),
        "activity.personal-rest": Prior(raised: true, share: 0.70),
        "activity.social": Prior(raised: true, share: 0.60),
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
              hypothesis.outcome.higherIsBetter == true,
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
    static func build(for input: EngineInput, resamples: Int = 2000) -> [Recommendation] {
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
                // derived from it. A heart-rate residual is a measurement to show,
                // never a thing to move a meeting for.
                && $0.hypothesis.outcome.higherIsBetter != nil
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
    static func headline(for input: EngineInput, resamples: Int = 2000) -> Recommendation? {
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

        switch finding.publishedType {
        case .bestTimeWindow, .drainingTimeWindow, .durationSweetSpot:
            if let experiment = finding.hypothesis.experiment { return experiment }
            return finding.publishedType == .drainingTimeWindow
                ? "Try moving one \(label.lowercased()) block to another hour this week."
                : "Try putting one block you care about into your \(label.lowercased()) this week."

        case .activityEnergizer:
            guard let window else { return "Try giving \(label) a block of its own this week." }
            return "Try giving \(label) one of your \(window) blocks this week."

        case .activityDrain:
            guard let window else { return "Try moving one \(label) block elsewhere in the week." }
            return "Try keeping \(label) out of your \(window) this week."

        case .workdayContrast:
            return finding.comparison.delta > 0
                ? "Try borrowing one thing from your days off into a workday this week."
                : "Try taking one thing that works on a workday into a day off this week."

        case .sleepContext, .bodyContext:
            // The claim is about which days go better, so the only thing it
            // supports is *when* to put a block. It cannot support telling anybody
            // to sleep more or move more, which would be advice the data does not
            // reach and the app is not allowed to give.
            guard let metric = HealthMetric(rawValue: Surprise.pattern(of: finding).subject) else { return nil }
            let better = finding.comparison.delta > 0 ? metric.higherPhrase : metric.lowerPhrase
            return "Try keeping your bigger blocks for the days \(better)."

        // Nothing in the registry produces these, and inventing a suggestion for a
        // claim shape that has never been tested would be a promise about evidence
        // that does not exist.
        case .performanceFeelingSplit, .fragmentation, .emergingChange:
            return nil
        }
    }
}
