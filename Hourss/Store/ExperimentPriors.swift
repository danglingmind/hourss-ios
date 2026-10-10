import Foundation

/// The offer for somebody the app has read nothing about, whose reason is what is
/// expected of people in general.
///
/// **The hole this fills, and it is the one the whole thread began with.** Every
/// other proposal in this app is built from a comparison. `ExperimentDesign` needs a
/// `Finding`, a finding needs six rated days on each side, and `ExperimentGaps` needs
/// a side thin enough to be worth filling — all three read the record. So the person
/// whose days do not vary, the fixed routine with the flat record, is the person with
/// the most to gain from "try something different" and was the one person the app
/// could not say it to. `ExperimentStarters` did not close it either: its premise *is*
/// a Health reading, so a phone with no Health history produces nothing at all.
///
/// This source reads neither. It needs the person's stated priorities and their
/// activity names, both of which exist the moment onboarding closes.
///
/// **Where the reason comes from, and the licence for it.** `Surprise.priors` holds
/// what is ordinarily true of people, and the boundary note above that table has
/// always said the numbers decide what to say first and nothing else. `PRD-VITALS.md`
/// §9 decides that a prior may also supply the *reason*, in a proposal's premise and
/// nowhere else, provided it is stated as a question about this person rather than a
/// fact about them:
///
/// > Mornings suit focused work for a lot of people. Nobody knows yet whether they
/// > suit you — two weeks would say.
///
/// That reverses `NarrationGuard`'s population ban in exactly one function, and the
/// reversal is the most heavily tested thing in this feature because the accuracy
/// lives entirely in the framing and framing erodes. `ExperimentCopy.priorPremise`
/// writes the sentence and checks itself; this file decides which question it is
/// about. Neither ever sees a share: `Surprise.expectedRaised` hands back keys and no
/// numbers, so there is no figure here to leak into a sentence.
///
/// **A prior chooses the question. The person's own data decides the answer.** Which
/// is why this ranks below everything measured. Two weeks of somebody's ratings beats
/// every row of that table about them, and the ranking at the offer chain is how that
/// is enforced rather than a comparison somewhere: measured proposals first, then
/// gaps, then this, then a Health-seeded starter.
///
/// **Only an expectation that points upwards can be asked for.** A prior whose
/// direction is `raised: false` says people in general find that side reads *worse* —
/// the post-lunch dip, meetings, long blocks. Asking somebody to do more of it for a
/// fortnight would be the app spending two weeks of their life on a question it
/// already expects a sour answer to, and it is the one shape of this offer that would
/// be actively unkind. `Surprise.expectedRaised` drops them, so the filter is the
/// accessor rather than a condition here.
enum ExperimentPriors {

    // MARK: - Shapes with an expectation behind them

    /// One question this source could ask, before anything decides whether it is
    /// worth asking.
    ///
    /// The `key` is what `Surprise` is consulted about; the `shape` is what
    /// `ExperimentStarters.blueprint` turns into a registry id, labels, a caveat and a
    /// change; the `subject` is what `ExperimentCopy.priorPremise` states in words.
    /// Three fields rather than one because they come from three different places and
    /// must not be derived from each other — the key is the table's grammar, the shape
    /// is the registry's, and the subject is the copy's.
    private struct Candidate {
        let key: String
        let shape: ExperimentStarters.Shape
        let subject: ExperimentCopy.PriorSubject
    }

    /// The activity whose pairing rows stand for a priority's own kind of work.
    ///
    /// **This is about the table, not about this person.** A pairing row says what
    /// people in general expect of deep work in a band; whether *this* person has an
    /// activity called "Deep work" has nothing to do with whether that expectation
    /// exists, and the change a band proposal asks for — one session in your morning —
    /// names no activity at all. So the slug is fixed per priority rather than read
    /// off their picker.
    ///
    /// It must also be the kind of work the premise will name, or the sentence would
    /// state an expectation the table does not hold: `ExperimentCopy.priorWork` calls
    /// `focus` "focused work", and `activity.deep-work.*` is the row that is about.
    /// The two agree by failing closed — a priority with a slug here but no phrase
    /// there produces a nil premise and therefore no offer.
    private static func pairedActivity(for priority: Priority) -> String? {
        switch priority {
        case .focus: "deep-work"
        case .energy, .sleep, .movement, .calm, .balance: nil
        }
    }

    /// Every question this source could ask for one priority, in no particular order —
    /// `Surprise` decides the order, which is the entire point of consulting it.
    ///
    /// **Which priorities get nothing, and why that is right.** `sleep`, `movement`
    /// and `calm` ask only about body associations. The table has rows for those and
    /// they are the strongest rows in it, but the change for one is responsive
    /// scheduling keyed to a Health reading — "on a day you slept longer, do your
    /// longest session then" — which needs Health history this source exists to do
    /// without, and the only other change anybody could write would be an instruction
    /// about the body, which this app does not give at any confidence. So they are
    /// served by `ExperimentStarters` where Health exists and by nothing here.
    /// Pretending otherwise would be a premise with no row behind it, which is a
    /// population claim with a decoration on it.
    ///
    /// Durations are absent for an arithmetic reason rather than an editorial one:
    /// every duration row in the table points downwards, so none could ever be asked
    /// for.
    private static func candidates(for priority: Priority,
                                   activities: [Activity]) -> [Candidate] {
        var out: [Candidate] = []

        if priority.insightTypes.contains(.bestTimeWindow) {
            for band in TimeBucket.allCases {
                // **The pairing wins where there is one, and this is the whole of
                // phase 4's effect.** Deep work in a morning is a different
                // expectation from "mornings", and where the table holds the pairing
                // it is the better-aimed question — including where the two disagree,
                // which is the case that makes a pairing worth a key at all. Where
                // there is no pairing the band's own row answers, and where there is
                // neither the band is simply not asked about.
                let pairing = pairedActivity(for: priority).map {
                    Surprise.pairKey(activity: $0, band: band)
                }
                let key = pairing.flatMap { Surprise.hasExpectation(of: $0) ? $0 : nil }
                    ?? "timeOfDay.\(band.rawValue)"
                out.append(Candidate(key: key,
                                     shape: .time(band),
                                     subject: .band(band, priority)))
            }
        }

        if priority.insightTypes.contains(.activityEnergizer) {
            // Their own picker, in their own order, so the activity named is one they
            // can actually choose — the rule `ExperimentStarters` states as "an
            // activity nobody has is an instruction nobody can follow". An activity
            // the table has no row for is dropped by `expectedRaised`, which is also
            // how somebody's own invented activity stays neutral: the table is a list
            // of things everybody believes, not a list of things that count.
            for activity in activities where !activity.isArchived {
                out.append(Candidate(
                    key: "activity.\(HypothesisRegistry.slug(activity.name))",
                    shape: .activity(activity.name),
                    subject: .activity(activity.name)))
            }
        }

        if priority.insightTypes.contains(.workdayContrast) {
            out.append(Candidate(key: "workday.non", shape: .workday, subject: .daysOff))
        }

        return out
    }

    // MARK: - Building

    /// One prior-led offer per priority that has an expectation behind it, in the
    /// person's own order.
    ///
    /// - Parameter activities: the picker order, so an activity this names is one they
    ///   can choose. Archived ones are skipped.
    /// - Parameter measured: hypothesis keys the engine has already produced a finding
    ///   for. This stands down for those, as a starter does and for the same reason:
    ///   once there is enough of somebody's own record to read, the measured path owns
    ///   the question, and saying "nobody knows yet whether mornings suit you" about a
    ///   split the engine has read twelve days of would be the app contradicting
    ///   itself in public.
    /// - Parameter excluding: declines and everything already tested, as every other
    ///   source in this feature takes them. Re-offering a question somebody has
    ///   answered is the app not listening.
    static func offers(
        for priorities: [Priority],
        activities: [Activity] = [],
        measured: Set<String> = [],
        excluding: Set<String> = []
    ) -> [ExperimentDesign.Proposal] {
        // Nothing was said about what matters, so there is no area to work on and this
        // layer picks none on somebody's behalf. The same guard every other source
        // opens with.
        guard !priorities.isEmpty else { return [] }

        var out: [ExperimentDesign.Proposal] = []
        var used = excluding.union(measured)

        for (rank, priority) in priorities.enumerated() {
            let candidates = candidates(for: priority, activities: activities)
            let byKey = Dictionary(candidates.map { ($0.key, $0) },
                                   uniquingKeysWith: { first, _ in first })

            // Most expected first, and the share that ordered them never leaves
            // `Surprise`. The loop rather than the head, because a candidate can fall
            // through on its id being spoken for or its premise failing its own sweep,
            // and the next-best question is still worth asking.
            for key in Surprise.expectedRaised(among: candidates.map(\.key)) {
                guard let candidate = byKey[key],
                      let blueprint = ExperimentStarters.blueprint(for: candidate.shape),
                      !used.contains(blueprint.hypothesisId),
                      let proposal = proposal(blueprint,
                                              subject: candidate.subject,
                                              priority: priority,
                                              rank: rank)
                else { continue }
                used.insert(blueprint.hypothesisId)
                out.append(proposal)
                break
            }
        }
        return out
    }

    /// A blueprint and a subject, as something somebody can accept.
    ///
    /// **Everything but the premise is `ExperimentStarters`' work, reused unaltered.**
    /// The id comes from the registry, the labels and caveat come with it, and the
    /// change is `ExperimentCopy.change` — the same sentence the measured path asks
    /// for. Two wordings of one change is the drift `ExperimentCopy` exists to
    /// prevent, and it would be worst here: the day-one offer and the day-twelve offer
    /// would propose the same fortnight in two voices.
    ///
    /// Nil when the premise cannot be framed, which is the fail-closed path
    /// `ExperimentCopy.priorPremise` documents. No premise, no offer.
    private static func proposal(_ blueprint: ExperimentStarters.Blueprint,
                                 subject: ExperimentCopy.PriorSubject,
                                 priority: Priority,
                                 rank: Int) -> ExperimentDesign.Proposal? {
        guard let premise = ExperimentCopy.priorPremise(subject) else { return nil }

        return ExperimentDesign.Proposal(
            hypothesisId: blueprint.hypothesisId,
            outcome: blueprint.outcome,
            type: blueprint.type,
            // Nothing has been measured about this person's sessions, which is the
            // premise's second sentence in `Standing` form. A starter is also what the
            // card already reads as "Worth testing", which is true and implies no
            // measurement.
            standing: .starter,
            // What is ordinarily true of people, which is not about this person at all.
            basis: .nothingYet,
            focusLabel: blueprint.focusLabel,
            baselineLabel: blueprint.baselineLabel,
            premise: premise,
            // The same absence, named specifically enough to be checkable against
            // their own record. It is deliberately a sentence about *them* sitting
            // under a sentence about people in general: the dangerous adjacency is a
            // fact followed by an instruction, and this is the opposite of it — the
            // second line narrows the first from "nobody knows" to "nothing you have
            // logged says", which is the part a reader can verify.
            context: blueprint.unknown,
            change: blueprint.change,
            caveat: blueprint.caveat,
            priority: priority,
            priorityRank: rank,
            // Zero, and zero is the truth: no comparison stands behind this. Nothing
            // renders these for a starter — see `ExperimentStarters.proposal`, which
            // makes the same argument about the same three fields.
            evidenceDays: 0,
            figure: 0,
            baselineFigure: 0
        )
    }
}
