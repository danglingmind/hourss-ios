import Foundation

/// Proposals that create the contrast the engine is missing.
///
/// **The flaw this exists to fix.** Every other proposal in this app is a version of
/// "this looked good, do more of it". `ExperimentDesign` builds from a `Finding`,
/// and a finding only exists where somebody's own record already varies — six days
/// of mornings against six of something else. So the app learns from differences a
/// person has already made, and can say nothing at all to a person who has not made
/// any.
///
/// That is exactly backwards. Somebody with a fixed routine — the same hours, the
/// same work, every week — is the person with the most to gain from "try something
/// different", and was the one person the app had nothing to say to. Their Patterns
/// screen read *nothing stands apart*, which was true and useless.
///
/// `ExperimentStarters` did not close it either: it builds from stated priorities
/// and Health readings and **never looks at what somebody logs**, so it can propose
/// a morning session to somebody who already works every morning. That is a
/// fortnight spent making one side of a comparison even heavier than it was.
///
/// **What this does instead.** `Engine.pending` already names, for every question
/// the engine cannot ask, exactly which side is thin and by how many days. "No
/// sessions in your evening yet" is the most actionable sentence the app owns. This
/// turns it into an offer: do the thing you have never done, for a fortnight, and at
/// the end the question is answerable — by you, about you.
///
/// The experiment *is* the way out of the dead end. A fortnight of giving one
/// activity its own block is roughly six days of it, which is the floor, so a gap
/// experiment ends with the comparison it was short of.
///
/// **Activities only, and that is a correction rather than a scope.** The first
/// version offered any empty side, time of day included, and one example killed it:
/// somebody whose work ends at three and who then sleeps has no evening sessions
/// because they have no evenings. Reasoning from absence points at exactly the hours
/// a person does not have. `isActivityGap` is where that line now sits.
///
/// **It is not a stronger claim than a starter.** Nothing has been measured about
/// this split — that is the point of it being pending — so these carry
/// `Standing.starter` and say so. What makes them better than a Health-seeded
/// starter is not confidence but relevance: the absence is a fact about this
/// person's own record rather than a reading about something else.
enum ExperimentGaps {

    /// One gap-filling proposal per priority that has no better offer.
    ///
    /// - Parameter pending: from `Engine.pending`. Runs no bootstrap, so this costs
    ///   nothing beyond the registry pass the caller has already paid for.
    /// - Parameter excluding: declined and already-tested keys, as everywhere else.
    ///   Re-offering a question somebody has answered is the app not listening.
    static func gaps(
        for priorities: [Priority],
        pending: [Engine.Pending],
        excluding: Set<String> = []
    ) -> [ExperimentDesign.Proposal] {
        var out: [ExperimentDesign.Proposal] = []
        var used: Set<String> = excluding

        for (rank, priority) in priorities.enumerated() {
            let candidates = pending.filter {
                priority.insightTypes.contains($0.hypothesis.type)
                    && !used.contains($0.hypothesis.id)
                    // The focus side is the one somebody can add days to by doing
                    // the thing. A question whose *other* side is thin is not a gap
                    // to fill — it is a record with everything in one place, and the
                    // answer there is to do something else entirely, which some
                    // other priority's gap already proposes.
                    && $0.focusDays < $0.gate
                    && ExperimentDesign.experimentableTypes.contains($0.hypothesis.type)
                    // Activities only. See `isActivityGap`.
                    && isActivityGap($0)
            }

            // The emptiest side first. A question with nothing on it at all is a
            // bigger hole than one two days short, and filling it buys the engine
            // more than topping up a side that nearly works.
            //
            // This is the one place ordering by distance is right, and it is not the
            // ordering `PRD-LOCKS.md` §6 refuses: that one forbids *showing* a list
            // sorted by closeness, which turns a record into a chore. This picks one
            // offer and never shows the ranking.
            guard let gap = candidates.min(by: { $0.focusDays < $1.focusDays }),
                  let proposal = proposal(from: gap, priority: priority, rank: rank)
            else { continue }

            used.insert(gap.hypothesis.id)
            out.append(proposal)
        }
        return out
    }

    /// Whether an absence is a choice somebody made rather than a life they lead.
    ///
    /// **This is the whole of what survived the 3pm objection.** The first version of
    /// this file offered a test for any empty side, time of day included — "no
    /// sessions in your evening yet, try some". For somebody whose work ends at three
    /// and who then sleeps, the empty evening is not a gap. It is their life, and an
    /// app that reads it as a hole is talking without knowing anything.
    ///
    /// An activity is different in kind. "You have never given Deep work a session of
    /// its own" is about a choice between things somebody already does, inside hours
    /// they already have. Nothing about it asks them to be awake at a time they are
    /// not, and what is proposed is a rearrangement rather than an addition.
    ///
    /// Duration is the near case and is excluded with the rest: a record with no long
    /// sessions may belong to somebody whose day cannot hold one, which is the same
    /// mistake wearing different clothes.
    ///
    /// Hours come back by another route — `PRD-VITALS.md`, where the curve is fitted
    /// on the hours somebody actually lives in and so can only ever name one of those.
    private static func isActivityGap(_ gap: Engine.Pending) -> Bool {
        gap.hypothesis.id.hasPrefix("activity.")
    }

    /// Everything a measured proposal has, with the absence standing in for evidence.
    private static func proposal(
        from gap: Engine.Pending,
        priority: Priority,
        rank: Int
    ) -> ExperimentDesign.Proposal? {
        let hypothesis = gap.hypothesis
        guard let change = ExperimentCopy.change(type: hypothesis.type,
                                                 focusLabel: hypothesis.focusLabel,
                                                 metric: nil,
                                                 outcome: hypothesis.outcome)
        else { return nil }

        return ExperimentDesign.Proposal(
            hypothesisId: hypothesis.id,
            outcome: hypothesis.outcome,
            type: hypothesis.type,
            standing: .starter,
            // An absence in their record. About them in a sense, and the weakest thing
                        // in this app to reason from — silence is not evidence.
            basis: .nothingYet,
            focusLabel: hypothesis.focusLabel,
            baselineLabel: hypothesis.baselineLabel,
            premise: ExperimentCopy.gapPremise(gap),
            // The absence itself, quietly, under the premise — the same place a
            // Health-seeded starter puts its reading. It is the evidence for the
            // offer without being evidence for an outcome.
            context: QuestionCopy.waiting(gap),
            change: change,
            caveat: hypothesis.caveat,
            priority: priority,
            priorityRank: rank,
            evidenceDays: 0,
            figure: 0,
            baselineFigure: 0
        )
    }
}
