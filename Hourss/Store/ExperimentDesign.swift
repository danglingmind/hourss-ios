import Foundation

/// Turning something the engine noticed into a change somebody can actually make.
///
/// **Three sources, one shape.** A proposal comes from a claim that cleared the
/// interval gate and the correction, from a lead that has not, or — when neither
/// exists because nothing has been rated yet — from `ExperimentStarters`, which
/// reads a premise off Health history and aims a change at a hypothesis the
/// registry has not minted yet. The card says which. The difference is in
/// `Standing` and in how much evidence is quoted, never in how the change is
/// phrased: a test is a test, and dressing an early one in hedged language would
/// make the honest label redundant and the copy worse.
///
/// This file builds the first two. `ExperimentStarters` builds the third and
/// borrows this file's `Proposal` and `ExperimentCopy`'s wording wholesale, so a
/// starter and a finding propose the same fortnight in the same words.
///
/// **A lead is safe to show because of `Shrinkage`, not in spite of it.** A mean of
/// four afternoons is mostly noise, and the noisiest group produces the most
/// extreme number, so the most striking early lead is usually the least real. The
/// figure a proposal quotes is therefore always the shrunk estimate — pulled toward
/// this person's own grand mean by how much evidence stands behind it — and the day
/// count is quoted beside it. That machinery was built for layer 4 and until now
/// nothing showed its output.
///
/// **Why so few hypotheses can become experiments.** Three filters, each of which
/// removes a shape that cannot honestly be tested:
///
/// 1. **The outcome must be directed.** The same filter `Recommendations.build`
///    applies: a heart-rate residual has no better side, so there is nothing to aim
///    at and no result to read.
/// 2. **The focus side must be the better side.** An experiment is measured by how
///    many days the focus group gained, so it can only ever test *increasing* a
///    group. Asking somebody to do more of the thing that reads worst is perverse,
///    and a draining window's own mirror image — the window that reads best — is
///    usually a separate hypothesis that qualifies on its own.
/// 3. **The change must be something a person can do.** A health association and a
///    workday contrast both pass, but only as *responsive scheduling*: the
///    condition cannot be moved, so the change is what gets put against it. "On a
///    day after a longer night, put your bigger block in" is in; "sleep more" is
///    not, because that is advice the data does not reach and the app is not
///    allowed to give.
///
/// **`workdayContrast` was excluded here and should not have been.** The reasoning
/// was that nobody can move which days are workdays, which is true and is not the
/// question. Its focus side is *non-workdays*, so the change — put a block on your
/// days off — adds days to the focus group exactly as every other experiment does,
/// and it is as testable as the health associations that were admitted on identical
/// grounds. Excluding it left `balance` with no experiment at all, which was
/// recorded as a hole to be filled by a later phase when it was really a filter
/// applied one step too early.
///
/// `drainingTimeWindow` and `activityDrain` stay out, and that is filter 2 rather
/// than filter 3: adherence counts days gained on the focus side, so there is no
/// way to test doing *less* of something by doing more of it.
enum ExperimentDesign {

    /// How much is behind a proposal, which the card states plainly.
    /// `CaseIterable` so a test can assert a property over *every* standing rather
    /// than over the three that exist today — the point being that adding a fourth
    /// without giving it its own eyebrow fails the suite instead of silently
    /// borrowing another standing's word, which is the exact mistake `.starter`
    /// shipped with.
    enum Standing: String, Equatable, CaseIterable {
        /// Cleared the interval gate and the correction. Day 12 at the earliest.
        case confirmed
        /// Directional, with enough days to be worth a fortnight and not enough to
        /// be claimed. Shown as something to test, never as something known.
        case lead

        /// Nothing measured about this person's sessions at all. A premise read off
        /// Health history and a change aimed at a hypothesis the registry has not
        /// minted yet, because they have not logged enough for it to exist.
        ///
        /// **Why a third case rather than reusing `.lead`.** A lead has a measured
        /// effect behind it and quotes it: `ExperimentCopy.premise` writes "across 4
        /// days" precisely because a lead without its count would read as a claim,
        /// and `standing(of:)` cannot return `.lead` with fewer than
        /// `leadMinimumDays` on each side. A starter filed as `.lead` would be a
        /// value violating that invariant — `evidenceDays == 0` — and any code that
        /// trusted it, here or in six months, would print "across 0 days" on a card.
        ///
        /// It also carries the precedence rule for free. A real finding always beats
        /// a starter, so something at the merge point has to be able to tell them
        /// apart; with `.lead` reused that would be a second field beside the
        /// standing, and two fields that must agree are two fields that can
        /// disagree — the argument `Experiment.phase` already makes for computing a
        /// phase from its optionals rather than storing one.
        ///
        /// The cost is one case in one exhaustive switch (`ExperimentCopy.premise`).
        /// The two view sites that read the standing compare against `.confirmed`
        /// and need no change: a starter reads as "Worth testing", which is true and
        /// implies no measurement.
        case starter
    }

    /// A change on offer, before anybody has agreed to it.
    ///
    /// Carries its own copy because the proposal card and the resulting
    /// `Experiment` must say the same thing — `experiment(from:)` copies these
    /// strings across unchanged, so what somebody accepted is literally what they
    /// were shown.
    struct Proposal: Identifiable, Equatable {
        /// Derived from the hypothesis, so a proposal and the insight it came from
        /// share identity exactly as `Recommendation` does.
        var id: UUID { Engine.identity(of: hypothesisId) }

        let hypothesisId: String
        let outcome: Outcome
        let type: InsightType
        let standing: Standing
        let focusLabel: String
        let baselineLabel: String
        let premise: String
        /// The Health reading a starter was built from, shown quietly under the
        /// premise. Nil for anything measured, which has no second source.
        ///
        /// **Separate from `premise` so the two cannot sit adjacent.** Joined into
        /// one string, a Health sentence lands directly beneath the change and reads
        /// as the reason for it — "your sleep reads 48m shorter on Tuesdays" above
        /// "put one block in your morning" is two true sentences that together imply
        /// a relationship nobody has measured, which is precisely what the fortnight
        /// is for. Kept apart, the card can put the disclaimer under the change and
        /// drop the reading into the quiet register, where it reads as evidence that
        /// the app has their history rather than as evidence for the change.
        let context: String?
        let change: String
        let caveat: String
        /// Which stated priority this serves, and where it sat in their list.
        let priority: Priority
        let priorityRank: Int
        /// Distinct days behind the focus side so far. Quoted on a lead, because a
        /// lead without its count is a claim.
        let evidenceDays: Int
        /// Shrunk estimate for the focus group, and this person's own grand mean
        /// across that family of groups.
        let figure: Double
        let baselineFigure: Double

        /// Members only, matching `Recommendations` today. A lead is free: it is the
        /// first useful thing the app can offer, and putting the upsell in front of
        /// that sells nothing and costs the first week. A starter is free for the
        /// same reason, more so — it is the *only* thing the app can offer on day
        /// one, and charging for it would put the paywall in front of the first
        /// screen that does anything.
        var requiresMembership: Bool { standing == .confirmed }

        /// Whether this one can also be offered with its days drawn by the app.
        ///
        /// Computed from the type rather than stored, so it cannot drift from the
        /// filter that decides it. Independent of `standing`: a confirmed claim, a
        /// lead and a day-one starter can all be tested on drawn days, because what
        /// the draw needs is a change the person decides about a day — not evidence.
        /// A starter is the strongest case for it, in fact, and the hardest sell: it
        /// is the only offer the app has on day one, and drawing its days is the
        /// difference between a month that confirms and a month that tests.
        var canRandomise: Bool { ExperimentDesign.randomisableTypes.contains(type) }

        /// What a drawn window would ask of this person, or nil where it cannot be
        /// drawn. Here rather than in a view, like every other string in this feature.
        var randomisedAsk: String? {
            guard canRandomise else { return nil }
            return ExperimentCopy.randomisedAsk(
                windowDays: Experiment.randomisedWindowDays,
                assignedDays: Experiment.randomisedWindowDays / 2)
        }

        /// Whether this rests on nothing the app has measured about their sessions.
        ///
        /// Read at the merge point, where a real proposal has to win. Expressed
        /// against the standing rather than stored, so it cannot drift from it.
        var isStarter: Bool { standing == .starter }
    }

    /// Distinct days on each side before a lead is worth a fortnight.
    ///
    /// **This number does not currently bind, and the comment it replaces claimed
    /// otherwise.** It was written to say that three is what it takes to notice
    /// something while six is what it takes to claim it — a real distinction, and
    /// one this constant cannot express from here. `Engine.findings` drops any
    /// hypothesis without `Hypothesis.minimumDays` distinct rated days on *each*
    /// side before it builds a `Finding` at all, that default is six, and nothing in
    /// `HypothesisRegistry` overrides it. So no finding with three to five days a
    /// side ever reaches `standing(of:)`, and the effective lead floor is the
    /// engine's six.
    ///
    /// Kept rather than deleted, as a floor that can only ever be stricter than the
    /// engine's and never looser: if `minimumDays` is ever lowered for some family,
    /// this is what stops leads appearing on two days of evidence. Raise it above
    /// six to make it bite; anything at or below six is inert.
    ///
    /// The practical cost of the old reading is that rung 2 arrives about a week
    /// later than the PRD promised, which is what makes phase 3's day-one starters
    /// load-bearing rather than merely nice.
    static let leadMinimumDays = 3

    /// Types whose days the app can draw. **Filter 4**, and it is narrower than the
    /// other three.
    ///
    /// A drawn assignment works by deciding, before anything happens, which days
    /// carry the change — so it only means anything where carrying the change is
    /// something the person decides about a day. Putting a block in the morning,
    /// ending one at a particular length, giving an activity a block of its own: all
    /// three are decisions about a day, and a day can be handed either of them.
    ///
    /// The two responsive families cannot be drawn, and it is worth being exact about
    /// why, because they pass filters 1 to 3 comfortably. `sleepContext` and
    /// `bodyContext` split on a Health reading, and the app can draw days but cannot
    /// make a drawn day a day of longer sleep; `workdayContrast` splits on the
    /// calendar, and a drawn day is not a day off. In both cases the assigned and
    /// unassigned arms would differ in nothing but the draw, the measured contrast
    /// would be between two indistinguishable halves of a month, and the result would
    /// wear a randomised test's clothes with none of its content. That is a worse
    /// failure than not offering it, because it would be *more* convincing and less
    /// true.
    ///
    /// The draining families are out one filter earlier, as they always were: a drawn
    /// window still counts days the change happened on, and there is no way to test
    /// doing less of something by doing more of it.
    static let randomisableTypes: Set<InsightType> = [
        .bestTimeWindow, .durationSweetSpot, .activityEnergizer
    ]

    /// Types a change can honestly be built for. See filter 3 above.
    static let experimentableTypes: Set<InsightType> = [
        .bestTimeWindow, .durationSweetSpot, .activityEnergizer,
        .sleepContext, .bodyContext, .workdayContrast
    ]

    // MARK: - Building

    /// Proposals for one engine run, in the person's own order of priorities.
    ///
    /// - Parameter declined: hypothesis keys this person has already said no to,
    ///   and keys they have already tested. Both are excluded for the same reason:
    ///   re-offering either is the app having forgotten, which is not a defence.
    static func proposals(
        for input: EngineInput,
        excluding declined: Set<String> = [],
        resamples: Int = Statistics.resamples
    ) -> [Proposal] {
        let findings = Engine.applyingCorrection(to: Engine.findings(for: input, resamples: resamples))
        return proposals(from: findings, input: input, excluding: declined)
    }

    /// - Parameter findings: already corrected, so `isReportable` can be trusted to
    ///   separate the two standings. Passing uncorrected findings would promote
    ///   every lead to confirmed.
    static func proposals(
        from findings: [Finding],
        input: EngineInput,
        excluding declined: Set<String> = []
    ) -> [Proposal] {
        // Nothing was said about what matters, so there is no area to work on and
        // this layer picks none on somebody's behalf.
        guard !input.priorities.isEmpty else { return [] }

        let eligible = findings.filter { isEligible($0) && !declined.contains($0.hypothesis.id) }
        guard !eligible.isEmpty else { return [] }

        var out: [Proposal] = []
        var used: Set<String> = []

        for (rank, priority) in input.priorities.enumerated() {
            let candidates = Surprise.ranked(eligible.filter {
                priority.insightTypes.contains($0.publishedType) && !used.contains($0.hypothesis.id)
            })
            /// The most surprising of these that there is actually something to
            /// propose about.
            ///
            /// Walking down the list rather than taking the head and giving up is
            /// not a weakening — every entry here cleared `isEligible`, the same
            /// gates, in the same order — it only skips candidates
            /// `ExperimentCopy.change` has no change for. `Recommendations.build`
            /// has always walked its list for exactly this reason.
            ///
            /// It matters now in a way it did not before. Until direction was
            /// resolved per person, no `physiology.*` finding could clear
            /// `isEligible` at all; a confirmed calibration admits them, and
            /// `ExperimentCopy.change` reads a `HealthMetric` off the id's subject,
            /// which for `physiology.deep-work.…` is an activity slug and so is
            /// nil. Those findings also tend to *outrank* the health associations,
            /// because the surprise table has no prior for them and has a strong
            /// one for sleep. Taking the head and bailing would therefore let a
            /// newly-admitted candidate claim a priority's slot and yield nothing,
            /// silently costing that priority the proposal it used to get — an
            /// unlock that makes the feature quieter.
            func firstProposal(_ among: [Finding]) -> (finding: Finding, proposal: Proposal)? {
                for candidate in among {
                    if let proposal = proposal(from: candidate, priority: priority,
                                               rank: rank, input: input) {
                        return (candidate, proposal)
                    }
                }
                return nil
            }

            // A confirmed claim outranks a lead however surprising the lead is:
            // offering the weaker of two available tests would be choosing to know
            // less. Within a standing, surprise decides.
            guard let chosen = firstProposal(candidates.filter { standing(of: $0) == .confirmed })
                ?? firstProposal(candidates) else { continue }
            used.insert(chosen.finding.hypothesis.id)
            out.append(chosen.proposal)
        }
        return out
    }

    /// The one to lead with. Nil is a real answer and the common one early on.
    static func headline(
        for input: EngineInput,
        excluding declined: Set<String> = [],
        resamples: Int = Statistics.resamples
    ) -> Proposal? {
        proposals(for: input, excluding: declined, resamples: resamples).first
    }

    // MARK: - Eligibility

    /// Whether a finding could become a change at all. The three filters, in order
    /// of how much they remove.
    static func isEligible(_ finding: Finding) -> Bool {
        // The calibration directs; it is never itself a thing to test. Its focus
        // side is "sessions where your heart rate ran above your usual", so the only
        // change that could add days to it is a change to a heart rate, and nothing
        // in this app asks for one.
        //
        // Stated here as a rule rather than left to `ExperimentCopy.change`
        // returning nil for want of a `HealthMetric`. That nil is an accident of how
        // the metric is read off the id — it happens to be right, which is not the
        // same as being a decision, and a refusal this important should be
        // discoverable where the refusals live.
        guard finding.hypothesis.id != HypothesisRegistry.residualCalibrationId else { return false }

        // The resolved direction, which for a residual is nil until this person's
        // own calibration has confirmed and `true` or `false` after. This is the
        // filter that made the whole `physiology.*` family unreachable.
        guard experimentableTypes.contains(finding.publishedType),
              finding.higherIsBetter == true
        else { return false }

        // The focus side has to be the better side, because adherence is measured
        // by days gained on it.
        guard finding.comparison.delta > 0 else { return false }

        return standing(of: finding) != nil
    }

    /// Confirmed, a lead, or not enough to be either.
    static func standing(of finding: Finding) -> Standing? {
        if finding.isReportable { return .confirmed }
        let comparison = finding.comparison
        guard comparison.focusDays >= leadMinimumDays,
              comparison.baselineDays >= leadMinimumDays
        else { return nil }
        return .lead
    }

    // MARK: - Assembly

    private static func proposal(
        from finding: Finding,
        priority: Priority,
        rank: Int,
        input: EngineInput
    ) -> Proposal? {
        guard let standing = standing(of: finding),
              let change = ExperimentCopy.change(for: finding) else { return nil }

        let figures = estimate(for: finding, in: input.observations)
        return Proposal(
            hypothesisId: finding.hypothesis.id,
            outcome: finding.hypothesis.outcome,
            type: finding.publishedType,
            standing: standing,
            focusLabel: finding.hypothesis.focusLabel,
            baselineLabel: finding.hypothesis.baselineLabel,
            premise: ExperimentCopy.premise(for: finding, standing: standing, days: figures.days),
            // A measured proposal's premise is the claim itself; there is no second
            // reading sitting behind it.
            context: nil,
            change: change,
            caveat: finding.hypothesis.caveat,
            priority: priority,
            priorityRank: rank,
            evidenceDays: figures.days,
            figure: figures.figure,
            baselineFigure: figures.grandMean
        )
    }

    /// The commitment somebody agreed to, from the proposal they were shown.
    ///
    /// Copies the strings across rather than regenerating them, so that what is
    /// stored is literally what was on screen. `Experiment`'s own documentation
    /// explains why that matters months later.
    static func experiment(from proposal: Proposal, startedAt: Date,
                           windowDays: Int = Experiment.defaultWindowDays) -> Experiment {
        Experiment(
            hypothesisId: proposal.hypothesisId,
            outcome: proposal.outcome,
            startedAt: startedAt,
            windowDays: windowDays,
            focusLabel: proposal.focusLabel,
            baselineLabel: proposal.baselineLabel,
            // Always true in this phase, by filter 2. Stored anyway, because the
            // record of what was predicted is what makes the verdict a test.
            predictsHigher: true,
            premise: proposal.premise,
            change: proposal.change,
            caveat: proposal.caveat
        )
    }

    /// The commitment somebody agreed to, with the days drawn by the app.
    ///
    /// **Nil rather than a fallback to the chosen kind.** A caller asking for a drawn
    /// window on a hypothesis whose days cannot be drawn has a bug, and silently
    /// handing back the ordinary kind would mean somebody tapped "pick the days for
    /// me" and got an experiment with no days in it — the one failure here that
    /// produces no error and no wrong number, only a quietly weaker test than the one
    /// they chose.
    ///
    /// **The window is four weeks, not a fortnight.** `Experiment.randomisedWindowDays`
    /// records the arithmetic: half the days go to each arm, and six on each side
    /// needs twice as many days to draw from.
    ///
    /// **The assignment is made here, once, from the start date it is handed.** Not
    /// at proposal time: proposals are rebuilt on every engine run, so a draw made
    /// there would either need a seed fixed to the hypothesis — handing everybody who
    /// tests their mornings the same pattern of weekdays, which is a pattern this app
    /// measures — or it would change the day list between one glance at the card and
    /// the next. Not at settling time either, obviously: that is the thing phase 4
    /// exists to make impossible.
    static func randomisedExperiment(
        from proposal: Proposal,
        startedAt: Date,
        windowDays: Int = Experiment.randomisedWindowDays
    ) -> Experiment? {
        guard proposal.canRandomise,
              let change = ExperimentCopy.randomisedChange(
                type: proposal.type, focusLabel: proposal.focusLabel) else { return nil }

        return Experiment(
            hypothesisId: proposal.hypothesisId,
            outcome: proposal.outcome,
            startedAt: startedAt,
            windowDays: windowDays,
            focusLabel: proposal.focusLabel,
            baselineLabel: proposal.baselineLabel,
            // Filter 2 still holds — a drawn window counts days gained on the focus
            // side exactly as a chosen one does — so the prediction is still that the
            // assigned days read higher. Stored rather than assumed, because the
            // record of what was predicted is what makes either kind a test.
            predictsHigher: true,
            assignment: Experiment.Assignment.make(
                hypothesisId: proposal.hypothesisId,
                startedAt: startedAt,
                windowDays: windowDays),
            premise: proposal.premise,
            // The one string that is *not* carried from the proposal, and the reason
            // the proposal card has to show both offers rather than one: a drawn
            // window asks for particular days and for restraint on the rest, which is
            // a different ask in different words. What somebody accepted is still what
            // they were shown — `Proposal.randomisedAsk` is what the second control
            // sits under — but it is not the same sentence as the first control's.
            change: change,
            caveat: ExperimentCopy.randomisedCaveat(proposal.caveat, windowDays: windowDays)
        )
    }

    private struct Figures {
        let figure: Double
        let grandMean: Double
        let days: Int
    }

    /// Shrunk estimate for the focus side.
    ///
    /// Two groups rather than the whole family, because what a proposal quotes is
    /// the split it is about to test. `Shrinkage` with two groups pulls each toward
    /// their common centre, which is the correction a thin early group needs.
    private static func estimate(for finding: Finding, in observations: [EngineObservation]) -> Figures {
        let hypothesis = finding.hypothesis
        let groups = Shrinkage.groups(in: observations, outcome: hypothesis.outcome) { row in
            if hypothesis.focus(row) { return "focus" }
            if hypothesis.baseline(row) { return "baseline" }
            return nil
        }
        let result = Shrinkage.shrink(groups)
        let focus = result.estimates["focus"]
        return Figures(figure: focus?.shrunk ?? 0,
                       grandMean: result.grandMean,
                       days: focus?.days ?? finding.comparison.focusDays)
    }
}
