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
        resamples: Int = 2000
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
            // A confirmed claim outranks a lead however surprising the lead is:
            // offering the weaker of two available tests would be choosing to know
            // less. Within a standing, surprise decides.
            let chosen = candidates.first(where: { standing(of: $0) == .confirmed })
                ?? candidates.first
            guard let chosen,
                  let proposal = proposal(from: chosen, priority: priority,
                                          rank: rank, input: input) else { continue }
            used.insert(chosen.hypothesis.id)
            out.append(proposal)
        }
        return out
    }

    /// The one to lead with. Nil is a real answer and the common one early on.
    static func headline(
        for input: EngineInput,
        excluding declined: Set<String> = [],
        resamples: Int = 2000
    ) -> Proposal? {
        proposals(for: input, excluding: declined, resamples: resamples).first
    }

    // MARK: - Eligibility

    /// Whether a finding could become a change at all. The three filters, in order
    /// of how much they remove.
    static func isEligible(_ finding: Finding) -> Bool {
        guard experimentableTypes.contains(finding.publishedType),
              finding.hypothesis.outcome.higherIsBetter == true
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
