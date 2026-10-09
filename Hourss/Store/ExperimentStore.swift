import Foundation

/// What the store does about experiments: offer one, take one on, stop one, and
/// close one when its fortnight runs out.
///
/// An extension rather than more lines in `HourssStore`, for the reason the store's
/// own other extensions exist: this is one feature's worth of behaviour and reads
/// better next to itself than interleaved with session logging.
@MainActor
extension HourssStore {

    // MARK: - Reading

    /// The experiment currently running, if there is one.
    ///
    /// There is at most one, and `accept` is what guarantees it. Expressed as a
    /// `first(where:)` rather than a stored property because a stored "current"
    /// plus a list is two sources of truth that can disagree, and the list is the
    /// one that has to be right.
    var activeExperiment: Experiment? {
        experiments.first { $0.phase == .active }
    }

    /// A settled experiment the person has not seen the result of yet.
    ///
    /// Oldest first, so somebody who somehow has two waiting is shown them in the
    /// order they happened rather than the order they were stored.
    var unacknowledgedExperiment: Experiment? {
        experiments.filter { $0.phase == .settled }
            .min { $0.settlement?.settledAt ?? $0.startedAt < $1.settlement?.settledAt ?? $1.startedAt }
    }

    /// Everything that has stopped being open, newest first.
    ///
    /// Settled, acknowledged and abandoned alike — the record screen lists all three
    /// and only excludes what is still running, which Today owns.
    ///
    /// Ordered by when the window stopped being open rather than by `settledAt`,
    /// because settling runs on the next launch or foreground and can be days late:
    /// sorting by it would order the list by when the app happened to notice rather
    /// than by when anything happened.
    ///
    /// Reads only stored values and runs no engine, so it is cheap enough for a view
    /// to call directly.
    var concludedExperiments: [Experiment] {
        experiments
            .filter { $0.phase != .active }
            .sorted { concluded($0) > concluded($1) }
    }

    /// The day an experiment stopped being open, whichever way it stopped.
    func concluded(_ experiment: Experiment, calendar: Calendar = .current) -> Date {
        experiment.abandonedAt ?? experiment.endsAt(calendar: calendar)
    }

    /// Hypothesis keys that must not be offered again.
    ///
    /// Declines and everything already tested, together. Both are "this has been
    /// put to them once", and the only thing that stops the app re-offering a
    /// fortnight somebody has already lived through is a record of it.
    ///
    /// Abandoned experiments are included. Somebody who started a test and stopped
    /// has answered the question of whether they want to run it, and asking again
    /// is not a fresh offer — it is the app not listening.
    var experimentKeysToExclude: Set<String> {
        declinedExperiments.union(experiments.map(\.hypothesisId))
    }

    /// What to offer, in the person's own order of priorities.
    ///
    /// Measured proposals first and day-one starters behind them — see `offers`. A
    /// caller that wants only the measured half can filter on
    /// `Proposal.isStarter`; nothing does today, because Today shows one card and
    /// the ordering has already decided which.
    ///
    /// Empty while one is running: the proposal surface has nothing to say to
    /// somebody mid-fortnight, and computing proposals they cannot accept would be
    /// a search run to be thrown away.
    ///
    /// Prefer `slotOutput()` on Today, which gets these and the recommendations from
    /// a single engine run. This is kept for callers that want only one of the two —
    /// `InsightDetailView` is one, and running the engine once there is the whole
    /// cost of opening a screen rather than a cost paid on every refresh.
    func experimentProposals(resamples: Int = 2000) -> [ExperimentDesign.Proposal] {
        guard activeExperiment == nil else { return [] }
        let input = EngineInput(observations: engineObservations, priorities: profile.priorities)
        let findings = Engine.applyingCorrection(to: Engine.findings(for: input, resamples: resamples))
        return offers(from: findings, input: input)
    }

    /// Recommendations and proposals, from one engine run.
    ///
    /// **Why this exists.** `Recommendations.build` and `ExperimentDesign.proposals`
    /// each run `Engine.findings` and then the correction, and Today needs both — so
    /// calling them separately tests sixty hypotheses at two thousand resamples
    /// twice, for two answers derived from the identical set of findings. Both layers
    /// already accept pre-corrected findings for exactly this reason.
    ///
    /// The findings are corrected once, here, and handed to both. Passing uncorrected
    /// findings to either would silently promote claims the feed refused to make —
    /// `ExperimentDesign` would read every lead as confirmed — which is why the
    /// correction happens at this level rather than being left to the callers.
    func slotOutput(resamples: Int = 2000)
        -> (recommendations: [Recommendation], proposals: [ExperimentDesign.Proposal]) {
        let rows = ObservationBuilder.rows(
            sessions: sessions,
            reflections: reflections,
            activities: activities,
            healthByDay: healthByDay,
            residuals: physiologyReadings,
            workdays: profile.workdays
        )
        let input = EngineInput(observations: rows, priorities: profile.priorities)
        let findings = Engine.applyingCorrection(to: Engine.findings(for: input, resamples: resamples))

        let recommendations = Recommendations.build(from: findings, input: input)
        // Nothing to offer mid-fortnight, and the guard is here as well as in
        // `experimentProposals` because this path does not go through it.
        let proposals = activeExperiment == nil ? offers(from: findings, input: input) : []
        return (recommendations, proposals)
    }

    /// Measured proposals, with day-one starters behind them.
    ///
    /// One function rather than two call sites, because the precedence rule — a real
    /// finding always beats a starter — is enforced by the order these come back in,
    /// and a second assembly of the same list is a second chance to get that order
    /// wrong. Both callers already have the corrected findings, which is what
    /// `measured` needs; recomputing them to learn which hypotheses the engine can
    /// read would be the duplicated engine run `slotOutput` exists to avoid.
    private func offers(from findings: [Finding], input: EngineInput)
        -> [ExperimentDesign.Proposal] {
        let proposals = ExperimentDesign.proposals(
            from: findings, input: input, excluding: experimentKeysToExclude)

        // Every hypothesis the engine got far enough to test. Past that point the
        // measured path owns the question, and a later source saying nothing is known
        // about it would be the app contradicting itself. Computed once and handed to
        // all four of them, because four recomputations are four chances to disagree.
        let measured = Set(findings.map(\.hypothesis.id))

        // The order below is the whole of `PRD-VITALS.md` §10 and it is a ranking by
        // *what the offer rests on*, strongest first: this person's own ratings, then
        // their own body, then what is expected of people in general, then an absence
        // in their own record, then a Health reading about something else.
        //
        // Assembled in one function for the reason the function exists — the
        // precedence rule is enforced by the order the list comes back in rather than
        // by a comparison somewhere, so a second assembly is a second chance to get it
        // wrong.

        // Vitals first behind the measured findings, because a place where somebody's
        // own heart rate sits five beats apart is a fact about them, which every
        // source below this line is not. `completing` skips a priority already served
        // above it, so this never puts a second offer on one focus area.
        // First among the unmeasured sources, because it is the only one that reads
        // the thing the app is actually about. Vitals reads heart rate, which is a
        // proxy for how a session felt; the prior reads what is true of people in
        // general, which is not about this person at all. This reads their own
        // ratings. `PRD-HOURS.md` §5 and open decision 1.
        //
        // It has nothing to say to most records, by construction: `RatingShape`
        // refuses any hour without evidence on both sides of it, so somebody who logs
        // only in the evening falls straight through to the sources below — which is
        // what those sources are for.
        let wake = WakeShape.usualWake(from: sessions)
        let withHours = ExperimentHours.completing(
            proposals,
            priorities: input.priorities,
            shape: RatingShape.fit(input.observations),
            observations: input.observations,
            wake: wake,
            measured: measured,
            excluding: experimentKeysToExclude
        )

        let withVitals = ExperimentVitals.completing(
            withHours,
            priorities: input.priorities,
            shape: dayShape,
            // Calibrated where the person's own residual has been resolved, which is
            // what lets the premise name a direction; uncalibrated otherwise, where it
            // may only name the place. §10 ranks those two apart and this is the one
            // value that separates them.
            direction: OutcomeDirection.resolved(from: findings),
            observations: input.observations,
            // From the nights already on the record rather than a fresh Health read:
            // `importFromHealth` writes each one with its real end, so this is
            // offline, needs no permission the person has not given, and costs a pass
            // over sessions. `WakeShape` refuses rather than guesses when somebody
            // has no usual waking time, and the gate opens when it does.
            wake: wake,
            measured: measured,
            excluding: experimentKeysToExclude
        )

        // Then what is expected of people in general — the only source here that rests
        // on nothing about this person at all, which is why it sits below everything
        // that does and why §9 makes it say so in its own premise.
        //
        // Filtered by priority rather than passed a shortened list: `ExperimentPriors`
        // reads `priorityRank` off the position in what somebody actually ranked, and
        // handing it a filtered list would have it report itself as their first
        // priority because the two above it were served elsewhere.
        let served = Set(withVitals.map(\.priority))
        let withPriors = withVitals + ExperimentPriors.offers(
            for: input.priorities,
            activities: pickableActivities,
            measured: measured,
            excluding: experimentKeysToExclude.union(withVitals.map(\.hypothesisId))
        ).filter { !served.contains($0.priority) }

        // Gaps sit between what has been measured and what Health can seed.
        //
        // **Behind anything measured**, because an offer resting on this person's own
        // ratings beats one resting on their own silence.
        //
        // **Ahead of a Health-seeded starter**, because a gap is a fact about the
        // record the test will be measured in, while a starter is a reading about
        // something else — and because `ExperimentStarters` never looks at what
        // somebody logs, so it will happily propose a morning session to somebody
        // who already works every morning and spend a fortnight making one side of a
        // comparison heavier than it already was.
        //
        // This is the only offer in the app for a person whose days do not vary, who
        // is also the person with the most to gain from being asked to vary them.
        //
        // Below the two sources above it now, which is a change §10 made and the
        // reason is the same one that narrowed this source to activities: a gap
        // reasons from silence, and silence is the weakest thing in this app to
        // reason from. It still beats a Health-seeded starter, because the absence is
        // a fact about the record the test will be measured in.
        let servedAbove = Set(withPriors.map(\.priority))
        let withGaps = withPriors + ExperimentGaps.gaps(
            for: input.priorities,
            pending: Engine.pending(for: input),
            excluding: experimentKeysToExclude.union(withPriors.map(\.hypothesisId))
        ).filter { !servedAbove.contains($0.priority) }

        return ExperimentStarters.completing(
            withGaps,
            priorities: input.priorities,
            healthByDay: healthByDay,
            activities: pickableActivities,
            measured: measured,
            excluding: experimentKeysToExclude
        )
    }

    /// How much of the change has happened so far, for the active card.
    ///
    /// Reads the window without writing anything — `settle` is the only call that
    /// freezes a figure, and it is deliberately not this one.
    func reading(for experiment: Experiment, resamples: Int = 2000) -> ExperimentOutcome.Reading {
        ExperimentOutcome.read(
            experiment,
            hypothesis: hypothesis(for: experiment.hypothesisId),
            observations: engineObservations,
            resamples: resamples
        )
    }

    // MARK: - Writing

    /// Take on a proposal.
    ///
    /// - Returns: the experiment, or nil when one is already running.
    ///
    /// **Rejects rather than queues.** Two concurrent changes make both unreadable,
    /// which is the entire value of the feature, so this is a hard invariant and not
    /// a preference. Silently queueing would be worse than refusing: the person
    /// would have agreed to something that starts at a date nobody told them.
    @discardableResult
    func acceptExperiment(_ proposal: ExperimentDesign.Proposal,
                          now: Date = Date(),
                          windowDays: Int = Experiment.defaultWindowDays) -> Experiment? {
        guard activeExperiment == nil else { return nil }
        let experiment = ExperimentDesign.experiment(
            from: proposal, startedAt: now, windowDays: windowDays)
        experiments.append(experiment)
        persist()
        return experiment
    }

    /// Take on a proposal with the days drawn by the app.
    ///
    /// The second of two ways to accept the same offer, and a materially harder one:
    /// four weeks rather than two, particular days rather than most days, and the
    /// request to leave the rest alone. It is opt-in for that reason, and
    /// `ExperimentCopy.randomisedAsk` is what has to earn the tap.
    ///
    /// - Returns: the experiment, or nil when one is already running, when this
    ///   hypothesis's days cannot be drawn, or when the window is too short to be
    ///   worth drawing over.
    ///
    /// **The window floor is a refusal, not a clamp.** A drawn window hands half its
    /// days to each arm, so one shorter than twice `Experiment.minimumDays` cannot
    /// supply six days to both sides however well somebody adheres — it could only
    /// ever come back unreadable. Silently stretching it to four weeks would be the
    /// app changing the terms of something somebody agreed to; returning nil is the
    /// same answer `acceptExperiment` gives when one is already running, for the same
    /// reason.
    @discardableResult
    func acceptRandomisedExperiment(
        _ proposal: ExperimentDesign.Proposal,
        now: Date = Date(),
        windowDays: Int = Experiment.randomisedWindowDays
    ) -> Experiment? {
        guard activeExperiment == nil else { return nil }
        guard windowDays >= 2 * Experiment.minimumDays else { return nil }
        guard let experiment = ExperimentDesign.randomisedExperiment(
            from: proposal, startedAt: now, windowDays: windowDays) else { return nil }
        experiments.append(experiment)
        persist()
        return experiment
    }

    /// Say no, permanently.
    ///
    /// Recorded against the hypothesis rather than the proposal, because the
    /// proposal is rebuilt on every run and the thing being refused is the question.
    func declineExperiment(_ proposal: ExperimentDesign.Proposal) {
        declinedExperiments.insert(proposal.hypothesisId)
        persist()
    }

    /// Stop early.
    ///
    /// Free and uncounted. Nothing anywhere records how often somebody has done
    /// this, because that number has no use which is not a reproach — and an
    /// abandoned experiment carries no verdict, since nothing was tested.
    func abandonExperiment(_ experiment: Experiment, now: Date = Date()) {
        guard let index = experiments.firstIndex(where: { $0.id == experiment.id }),
              experiments[index].phase == .active else { return }
        experiments[index].abandonedAt = now
        persist()
    }

    /// Mark a result as seen, so it stops claiming the slot on Today.
    ///
    /// The figures stay. A result is part of this person's record once it exists,
    /// and acknowledging it is not the same as discarding it.
    func acknowledgeExperiment(_ experiment: Experiment, now: Date = Date()) {
        guard let index = experiments.firstIndex(where: { $0.id == experiment.id }),
              experiments[index].phase == .settled else { return }
        experiments[index].acknowledgedAt = now
        persist()
    }

    // MARK: - Settling

    /// Close any window that has run out.
    ///
    /// Called on launch and on returning to the foreground, the same two moments
    /// the health import and the physiology feed already run at — a fortnight ends
    /// while the app is shut far more often than while somebody is looking at it, so
    /// a timer would be the wrong mechanism even if it were cheap.
    ///
    /// - Parameter now: injected so a test can cross a date boundary. Never reads
    ///   the clock itself: two reads of `Date()` inside one decision is a bug this
    ///   codebase has already shipped once, in the slot picker.
    /// - Returns: whether anything settled, so a caller can decide to refresh.
    @discardableResult
    func settleClosedExperiments(now: Date = Date(), resamples: Int = 2000) -> Bool {
        var settledAny = false
        for index in experiments.indices where experiments[index].phase == .active {
            let experiment = experiments[index]
            guard experiment.hasClosed(at: now) else { continue }
            experiments[index] = ExperimentOutcome.settle(
                experiment,
                hypothesis: hypothesis(for: experiment.hypothesisId),
                observations: engineObservations,
                now: now,
                resamples: resamples
            )
            settledAny = experiments[index].settlement != nil || settledAny
        }
        if settledAny { persist() }
        return settledAny
    }

    /// The live hypothesis behind a stored key.
    ///
    /// Looked up rather than stored, because the predicate is a closure and because
    /// "morning" should mean whatever the registry means by morning today — the
    /// person was testing their mornings, not a definition. Nil is a real answer:
    /// the activity a hypothesis named may have been deleted since, which
    /// `ExperimentOutcome` turns into "cannot tell" rather than a failure.
    func hypothesis(for id: String) -> Hypothesis? {
        HypothesisRegistry.hypotheses(for: engineObservations).first { $0.id == id }
    }
}
