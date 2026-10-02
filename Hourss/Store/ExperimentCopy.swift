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
            // "Has read higher", never "is better" — no verb that implies the
            // pattern will hold.
            //
            // **Two forms, because "so far" is a lie past a certain count.** The
            // first was written for a thin lead and reads correctly at four days:
            // not much has been seen, and what has been seen leans one way. Real
            // data produces leads at sixteen and twenty days, because the floor is
            // six a side and a lead accrues evidence indefinitely without ever
            // clearing the gates — and at that point "so far" says the app has not
            // looked much, when it has looked a great deal and found nothing that
            // separates. Those are opposite statements about the same number.
            //
            // The line is the experiment window. Fewer days than a fortnight and
            // the group has not had a fortnight's worth of looking, so "so far" is
            // honest; more, and it has, and the honest sentence says what did not
            // happen instead.
            let unit = days == 1 ? "day" : "days"
            let label = finding.hypothesis.focusLabel
            if days < Experiment.defaultWindowDays {
                return "\(label) has read higher so far, across \(days) \(unit)."
            }
            return "\(label) has read a little higher across \(days) \(unit), "
                + "without pulling clear of the rest."
        case .starter:
            // Unreachable from this function, and a case rather than a `default`
            // so that a fourth standing is a compile error here instead of a
            // silent fall-through. `ExperimentDesign.standing(of:)` only ever
            // returns one of the two measured standings, and a starter's premise
            // is assembled by `ExperimentStarters` out of a Health fact because
            // there is no finding behind it to phrase.
            //
            // What it returns is still the honest sentence for a starter rather
            // than a trap: a premise is a line on a card, and if some future
            // caller does reach this, a plain true sentence is a better outcome
            // than a crash. Deliberately *not* the lead form — that one quotes a
            // day count, and a starter's count is zero.
            return starterUnknown(type: finding.publishedType,
                                  focusLabel: finding.hypothesis.focusLabel,
                                  baselineLabel: finding.hypothesis.baselineLabel,
                                  metric: metric(of: finding))
        }
    }

    // MARK: - Starter premise

    /// A starter's premise: what Health already shows, then what is not yet known.
    ///
    /// **Two sentences, and the second one is load-bearing.** The first is a
    /// `HealthDigest` sentence, carried verbatim — descriptive, about a Health
    /// reading, and already on screen as the daily fact, which is the same reason
    /// a confirmed premise reuses `hypothesis.phrase` rather than writing a second
    /// wording for one finding.
    ///
    /// On its own, though, a Health sentence sitting directly above a change reads
    /// as the reason for it. "Your sleep reads 48m shorter on Tuesdays than
    /// Saturdays" followed by "put one block in your morning" is two honest
    /// sentences that together imply a relationship nobody has measured — which is
    /// precisely what the fortnight is for. The second sentence is what stops that
    /// reading: it says in plain words that nothing logged speaks to this yet, so
    /// the Health reading is evidence that the app has their history and not
    /// evidence for the change.
    static func starterPremise(_ healthSentence: String, unknown: String) -> String {
        "\(healthSentence) \(unknown)"
    }

    /// What has not been read yet, named specifically enough to be checkable.
    ///
    /// Total rather than optional: every shape has something it has not read, and
    /// the generic arm is a true sentence about any two sides rather than a hole.
    /// Nothing here claims, instructs or compares to anybody — it states an
    /// absence, which is the one thing a starter knows for certain.
    static func starterUnknown(type: InsightType,
                               focusLabel: String,
                               baselineLabel: String,
                               metric: HealthMetric?) -> String {
        switch type {
        case .bestTimeWindow:
            return "Nothing you have logged says yet how your \(focusLabel.lowercased()) "
                + "sessions read against the rest of your day."

        case .durationSweetSpot:
            return "Nothing you have logged says yet how your \(focusLabel.lowercased()) "
                + "sessions read against your other lengths."

        case .activityEnergizer:
            return "Nothing you have logged says yet how your time in \(focusLabel) "
                + "reads against everything else."

        case .workdayContrast:
            return "Nothing you have logged says yet how your days off read against your workdays."

        // Named by the metric's own higher phrase, which is the wording the change
        // uses too — so the two sentences are plainly about the same days.
        case .sleepContext, .bodyContext:
            guard let metric else { return generic(focusLabel, baselineLabel) }
            return "Nothing you have logged says yet how your sessions read \(metric.higherPhrase)."

        // No starter targets these — `ExperimentStarters.Shape` has no case that
        // produces them and `ExperimentDesign.experimentableTypes` excludes them.
        // The generic form is here so that admitting a type later cannot produce a
        // premise with a hole in it.
        case .drainingTimeWindow, .activityDrain,
             .performanceFeelingSplit, .fragmentation, .emergingChange:
            return generic(focusLabel, baselineLabel)
        }
    }

    private static func generic(_ focusLabel: String, _ baselineLabel: String) -> String {
        "Nothing you have logged says yet how \(focusLabel.lowercased()) "
            + "reads against \(baselineLabel.lowercased())."
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
        change(type: finding.publishedType,
               focusLabel: finding.hypothesis.focusLabel,
               metric: metric(of: finding))
    }

    /// Which Health metric a finding split on, or nil for a finding that split on
    /// something else.
    ///
    /// Read off the id through `Surprise.pattern` rather than off the type, because
    /// `sleepContext` and `bodyContext` are both health associations and only the id
    /// says which metric. The id grammar is the registry's and is deliberately
    /// boring; insight identity already rides on it.
    private static func metric(of finding: Finding) -> HealthMetric? {
        HealthMetric(rawValue: Surprise.pattern(of: finding).subject)
    }

    /// The same change, from the three things that decide it rather than from a
    /// finding.
    ///
    /// Split out so that a starter — which has no finding, by definition — asks for
    /// the identical change in the identical words. Two wordings of one instruction
    /// is the drift this file exists to prevent, and it would be worse here than
    /// anywhere: the measured path and the day-one path would be proposing the same
    /// fortnight in two voices, and only one of them would be swept by whichever
    /// test somebody wrote first.
    static func change(type: InsightType, focusLabel: String, metric: HealthMetric?) -> String? {
        let label = focusLabel
        switch type {
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
            guard let metric else { return nil }
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

    // MARK: - Standing

    /// What a card calls itself, from how much is behind it.
    ///
    /// Here rather than at the three view sites that need it, for the reason the
    /// control titles below are here: a string authored inside a view body is a
    /// string no sweep can see, and three copies of this decision are three places
    /// it can drift.
    ///
    /// **A starter needs its own word, and shared one with a lead until now.** Both
    /// read "Worth testing", which is true of each and hides the only thing that
    /// separates them: a lead has six rated days on each side of a real split, and a
    /// starter has nothing at all behind it but a Health reading about something
    /// else. Telling somebody those are the same kind of offer is the quiet half of
    /// overclaiming — nothing false is said, and the weaker card borrows the
    /// stronger one's standing.
    static func eyebrow(for standing: ExperimentDesign.Standing) -> String {
        switch standing {
        case .confirmed: "Test what held up"
        case .lead: "Worth testing"
        // Names no evidence, because there is none. "Start" is doing the work
        // "worth" does in the lead's version, without implying anything was weighed.
        case .starter: "A place to start"
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
