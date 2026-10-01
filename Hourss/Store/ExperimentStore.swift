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
    /// Empty while one is running: the proposal surface has nothing to say to
    /// somebody mid-fortnight, and computing proposals they cannot accept would be
    /// a search run to be thrown away.
    func experimentProposals(resamples: Int = 2000) -> [ExperimentDesign.Proposal] {
        guard activeExperiment == nil else { return [] }
        return ExperimentDesign.proposals(
            for: EngineInput(observations: engineObservations, priorities: profile.priorities),
            excluding: experimentKeysToExclude,
            resamples: resamples
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
