import Foundation

/// Every sentence an experiment puts on screen.
///
/// **This is the only place in the app allowed to instruct.** `NarrationGuard`'s
/// `instruction` list bans "try", "consider", "aim to" and the rest, and that ban
/// stands everywhere it already applied: `Narration` describes and stops,
/// `RecordFacts` describes and stops. The guard was never run over
/// `Recommendation.action` and is not run over these, and the comment on the list
/// itself already says why — "the free tier proposes a test". This file is that
/// sentence, implemented.
///
/// **The causal and clinical bans are absolute, including here.** This is the trap,
/// because the natural way to report a successful test is forbidden vocabulary.
/// `improves`, `improve`, `helps`, `boosts`, `because`, `leads to` and `effect of`
/// are all on the causal list; `energy levels`, `intensity` and `stress` are on the
/// clinical one. So a result says where the numbers landed and stops:
///
/// | Not this | This |
/// | --- | --- |
/// | Morning blocks improve your focus. | Those blocks settled at 4.2 against your 3.4. |
/// | This helped, so keep it up. | It held up for two weeks. Worth keeping. |
/// | Earlier starts boost your energy. | Your earlier blocks read higher than the rest. |
///
/// A test sweeps every string this file can produce for causal, clinical and
/// population offences, mirroring the sweep `RecordFactsTests` already runs.
enum ExperimentCopy {

    // MARK: - Premise

    /// Why this is being offered, which claims nothing beyond what its standing
    /// supports.
    ///
    /// A confirmed premise reuses `hypothesis.phrase` — the sentence the feed
    /// already shows for that claim, which has been through the phrasing rules and
    /// is the wording this person may already have read on the Patterns tab. Writing
    /// a second sentence for the same finding is the drift the engine is built to
    /// prevent.
    ///
    /// A lead cannot borrow it, because that sentence is phrased as something known.
    /// It gets its own form, built around the day count so the reader can see how
    /// thin it is: the count is the caveat, and burying it would make the honest
    /// `Standing` label the only thing standing between a lead and a claim.
    static func premise(for finding: Finding,
                        standing: ExperimentDesign.Standing,
                        days: Int) -> String {
        switch standing {
        case .confirmed:
            return finding.hypothesis.phrase(finding)
        case .lead:
            // "So far" and a count, with no verb that implies the pattern will
            // hold. "Has read higher" rather than "is better".
            return "\(finding.hypothesis.focusLabel) has read higher so far, across \(days) "
                + (days == 1 ? "day" : "days") + "."
        }
    }

    // MARK: - Change

    /// The one change, concrete enough that a person knows whether they did it.
    ///
    /// Nil where nothing honest can be asked, which is not a gap to be filled: the
    /// shapes that return nil here are the ones `ExperimentDesign` documents as
    /// untestable, and inventing a change for them would be asking somebody to do
    /// something impossible and then measuring them on it.
    ///
    /// **"Most days" rather than a number.** An instruction to do something exactly
    /// eight times is a target to fail, and the measurement does not need it —
    /// adherence is counted from what was logged, so the copy can describe the
    /// direction and let the count speak at the end.
    static func change(for finding: Finding) -> String? {
        let label = finding.hypothesis.focusLabel
        switch finding.publishedType {
        case .bestTimeWindow:
            return "Put one block in your \(label.lowercased()) on most days this fortnight."

        case .durationSweetSpot:
            return "End one block at the \(label.lowercased()) mark on most days this fortnight."

        case .activityEnergizer:
            return "Give \(label) a block of its own on most days this fortnight."

        // Responsive scheduling, and the distinction that keeps it legal: this asks
        // somebody to choose *when* to put a block, never to change the reading. A
        // version of this that said "sleep longer" would be advice the data does not
        // reach, and the app does not give it.
        case .sleepContext, .bodyContext:
            guard let metric = HealthMetric(rawValue: Surprise.pattern(of: finding).subject) else { return nil }
            return "On a day \(metric.higherPhrase), put your bigger block in."

        // Responsive scheduling again, and the same distinction. Which days are
        // workdays cannot be moved; what goes on them can. The focus side of this
        // hypothesis is the days off, so putting a block there adds days to the
        // group being measured exactly as every other change does.
        case .workdayContrast:
            return "Put one block on each of your days off this fortnight."

        // Filter 2, not filter 3: adherence counts days gained on the focus side,
        // so there is no way to test doing less of something by doing more of it.
        // The rest have no action at all.
        // `ExperimentDesign.experimentableTypes` excludes these before this is
        // reached; the cases are here so that adding a type to that set without
        // writing its change is a compile error rather than a silent nil.
        case .drainingTimeWindow, .activityDrain,
             .performanceFeelingSplit, .fragmentation, .emergingChange:
            return nil
        }
    }

    // MARK: - Controls

    /// Titles for the four controls, here rather than in the view for the reason the
    /// rest of this file exists: every word an experiment shows is swept in one place,
    /// and a string authored inside a view body is a string no sweep can see.
    static let startTitle = "Start this"
    /// Says no to the question, not to the app. "Not this one" leaves the door open
    /// for the next proposal, which is accurate — a decline is permanent for one
    /// hypothesis and for nothing else.
    static let declineTitle = "Not this one"
    /// Plain, and deliberately not "Give up". Stopping is free and uncounted.
    static let stopTitle = "Stop this test"
    static let acknowledgeTitle = "Got it"

    /// Every control title, for the sweep.
    static let controlTitles = [startTitle, declineTitle, stopTitle, acknowledgeTitle]

    // MARK: - Result

    /// What the window produced, in one sentence.
    ///
    /// Each case states where the numbers landed and stops. None of them says the
    /// change was the reason, because a concurrent control over one fortnight does
    /// not reach that and the caveat shown beside this says so.
    static func result(for experiment: Experiment, settlement: Experiment.Settlement) -> String {
        let focus = figure(settlement.focusFigure)
        let baseline = figure(settlement.baselineFigure)

        switch settlement.verdict {
        case .heldUp:
            return "\(experiment.focusLabel) settled at \(focus) against your \(baseline) "
                + "across \(settlement.adherenceDays) days. It held up."

        case .didNotHoldUp:
            return "\(experiment.focusLabel) settled at \(focus) against your \(baseline) "
                + "across \(settlement.adherenceDays) days. No difference you could act on."

        case .cannotTell:
            return cannotTell(settlement)
        }
    }

    /// A short label for the verdict, for the card's own heading.
    static func verdictTitle(_ verdict: Experiment.Verdict) -> String {
        switch verdict {
        case .heldUp: "It held up"
        case .didNotHoldUp: "It did not hold up"
        case .cannotTell: "Not enough to tell"
        }
    }

    /// What was short, and what would have been enough.
    ///
    /// Names the number rather than only the shortfall, because "not enough" with no
    /// figure reads as the app withholding something. Says nothing about the change
    /// itself: nothing was tested, so there is nothing to report about it, and a
    /// sentence implying the change failed would be a verdict the evidence does not
    /// carry.
    private static func cannotTell(_ settlement: Experiment.Settlement) -> String {
        let floor = Experiment.minimumDays
        let adherence = settlement.adherenceDays
        let baseline = settlement.baselineDays

        if adherence < floor && baseline < floor {
            return "\(floor) days of each would have been enough to read. "
                + "There were \(adherence) and \(baseline)."
        }
        if adherence < floor {
            return "\(floor) days of it would have been enough to read. There were \(adherence)."
        }
        if baseline < floor {
            return "\(floor) days of the rest would have been enough to read against. "
                + "There were \(baseline)."
        }
        // Reached when the hypothesis has left the registry — the activity it named
        // may have been deleted. Says so without blaming the window.
        return "This one can no longer be read against your record."
    }

    /// One decimal, because the scale has five points and a second decimal would
    /// imply a precision five points do not have.
    private static func figure(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
