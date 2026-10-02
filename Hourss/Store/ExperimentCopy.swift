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
    /// **No longer what a card shows, and kept for what reads it.** The two halves
    /// are separate fields on `Proposal` now, so that the Health reading cannot sit
    /// directly beneath the change — see `Proposal.context`. This joins them in the
    /// order they are spoken, which is what the accessibility label and the copy
    /// sweep want: one string carrying everything a starter puts on screen.
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
    /// **"Session", never "block".** These said "block" for a long time, and the word
    /// appears nowhere else in this app: every other surface says sessions — "11h
    /// 20m logged across 5 sessions", "your morning sessions have felt more
    /// energizing". A reader met it for the first time in the one sentence they were
    /// being asked to act on, and the owner had to ask what it meant. One name per
    /// thing, and the name is the one the rest of the app already uses.
    ///
    /// **"Log", not "put".** "Put one block on a day off" does not say whether
    /// somebody is being asked to do something or to record something. It is both,
    /// and the measurable half is the record: adherence counts days carrying a rated
    /// session, so a day nobody logged did not happen as far as the window is
    /// concerned. The verb now says that.
    ///
    /// **"For two weeks", not "this fortnight".** Same length, plainer word, and it
    /// reads correctly beside the drawn window's four.
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
               metric: metric(of: finding),
               outcome: finding.hypothesis.outcome)
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
    /// - Parameter outcome: what the window will be measured on. Defaulted, because
    ///   every change written before phase 3 was measured on a rating and none of
    ///   their call sites should have to say so. It matters for exactly one case:
    ///   `physiology.*` and a health association both publish as `.bodyContext`, and
    ///   the outcome is the only thing that tells them apart.
    static func change(type: InsightType, focusLabel: String, metric: HealthMetric?,
                       outcome: Outcome = .feeling) -> String? {
        let label = focusLabel
        switch type {
        case .bestTimeWindow:
            return "Log one session in your \(label.lowercased()) on most days, for two weeks."

        case .durationSweetSpot:
            return "Let one session run to the \(label.lowercased()) mark on most days, for two weeks."

        case .activityEnergizer:
            return "Give \(label) a session of its own on most days, for two weeks."

        // Responsive scheduling, and the distinction that keeps it legal: this asks
        // somebody to choose *when* to put a block, never to change the reading. A
        // version of this that said "sleep longer" would be advice the data does not
        // reach, and the app does not give it.
        case .sleepContext, .bodyContext:
            // A physiology claim rather than a health association. Both publish as
            // `.bodyContext`; only the outcome separates them.
            //
            // **The lever is the activity and the measurement is the watch.** This
            // is the only experiment in the app that needs nobody to rate anything —
            // adherence counts days carrying a residual, not days carrying a rating —
            // and that is worth saying before somebody accepts it, because it is the
            // one offer here that asks less of them rather than more. Saying it also
            // stops the result arriving in bpm as a surprise.
            //
            // The change itself is `activityEnergizer`'s, deliberately: the thing
            // being moved is the same thing, and only the measurement differs. Two
            // wordings for one act would be the drift this file exists to prevent.
            if outcome == .heartRateResidual {
                return "Give \(label) a session of its own on most days, for two weeks. "
                    + "This one is read from your heart rate, so it needs no ratings."
            }
            guard let metric else { return nil }
            return "On a day \(metric.higherPhrase), do your longest session then."

        // Responsive scheduling again, and the same distinction. Which days are
        // workdays cannot be moved; what goes on them can. The focus side of this
        // hypothesis is the days off, so putting a block there adds days to the
        // group being measured exactly as every other change does.
        case .workdayContrast:
            return "Log one session on each of your days off, for two weeks."

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

    // MARK: - A drawn window

    /// The change, for a window whose days the app drew.
    ///
    /// **Why this cannot be the same sentence with a clause bolted on.** The chosen
    /// form says "on most days this fortnight", which is deliberately not a number —
    /// an instruction to do something exactly eight times is a target to fail, and
    /// adherence is counted from what was logged anyway. A drawn window inverts that:
    /// the days *are* the instruction, there is no latitude in them, and the sentence
    /// has to say so or the person will do the thing on the days that suit them and
    /// the contrast will be gone.
    ///
    /// **"And not on the rest" is load-bearing, not tidiness.** The second half of
    /// what makes a drawn window readable is the days without the change in them. If
    /// somebody does it every day the two arms differ in nothing and the verdict is
    /// that nothing can be read — so asking for the restraint up front is the
    /// difference between a month that answers and a month that does not. It is also
    /// the part that asks far more of somebody than any other offer in this app, and
    /// the proposal says so plainly rather than slipping it in here alone.
    ///
    /// Nil for every family whose focus side is not something a person decides about
    /// a day. See `ExperimentDesign.randomisableTypes`.
    static func randomisedChange(type: InsightType, focusLabel: String) -> String? {
        let label = focusLabel.lowercased()
        switch type {
        case .bestTimeWindow:
            return "Log one session in your \(label) on each of the days picked for you, "
                + "and not on the rest."

        case .durationSweetSpot:
            return "Let one session run to the \(label) mark on each of the days picked for you, "
                + "and not on the rest."

        case .activityEnergizer:
            return "Give \(focusLabel) a session of its own on each of the days picked for you, "
                + "and not on the rest."

        // Nil, and the cases are named rather than defaulted so that admitting a
        // family to `ExperimentDesign.randomisableTypes` without writing its sentence
        // is a compile error here instead of a proposal with no change in it.
        //
        // The two responsive families are the interesting refusals. A sleep or body
        // association's focus side is a Health reading, and a workday contrast's is
        // the calendar: the app can draw days for either, but the days it draws are
        // not days of higher sleep and cannot be made into days off, so the two arms
        // would differ in nothing a person could act on. Drawing days there would be
        // the form of a randomised test with none of its content.
        case .sleepContext, .bodyContext, .workdayContrast,
             .drainingTimeWindow, .activityDrain,
             .performanceFeelingSplit, .fragmentation, .emergingChange:
            return nil
        }
    }

    /// What is being asked, and what it buys. The paragraph the second control sits
    /// under.
    ///
    /// **This has to earn an opt-in, and overclaiming is how it would fail.** A drawn
    /// window asks for specific days, including days somebody would rather not, for
    /// twice as long as the ordinary offer. The only honest return on that is a
    /// stronger reading, so the sentence states what the reading becomes and stops
    /// well short of cause: days the person did not choose are what separates a change
    /// that held up from a month that was going well anyway. That is true, it is the
    /// most the design supports, and it is the whole argument for this phase in one
    /// sentence.
    ///
    /// Nothing here promises the change will work, and nothing hints that the app
    /// knows it will. `NarrationGuard`'s causal list is not the constraint that keeps
    /// it that way — `instruction` is the only list lifted in this file — but the
    /// shape of the claim is, and a test sweeps it alongside everything else.
    static func randomisedAsk(windowDays: Int, assignedDays: Int) -> String {
        "\(assignedDays) days out of the next \(windowDays), picked by the app before you "
            + "start — including days you would rather not. Days you did not choose are the "
            + "only ones that can tell a change that held up from a stretch that was going "
            + "well anyway."
    }

    /// The limit on a drawn window's result, appended to the hypothesis's own caveat.
    ///
    /// The hypothesis caveat still applies and is not replaced: whatever travels with
    /// a morning block still travels with it on a day the app picked. What the draw
    /// removes is the person's choice of *which* days, and what remains after it is
    /// one person and four weeks — which is what this says, without saying the word
    /// this app is not allowed to say about any of it.
    /// Takes the window length rather than naming four weeks, for the reason the
    /// drawn change does not call itself a fortnight: a caveat that describes a
    /// different commitment from the one being made is worse than no caveat, and the
    /// window is a parameter everywhere else in this feature.
    static func randomisedCaveat(_ base: String,
                                 windowDays: Int = Experiment.randomisedWindowDays) -> String {
        "\(base) One person, \(span(windowDays)), with the days picked before any of it "
            + "happened."
    }

    /// A window length in words.
    ///
    /// Spelled rather than written as a figure because every number this app shows is
    /// a measurement of somebody's own record, and a digit inside a caveat reads as
    /// one. The two lengths the app offers are named; anything else is a window a
    /// caller asked for and is reported as the count of days it is.
    private static func span(_ windowDays: Int) -> String {
        switch windowDays {
        case Experiment.randomisedWindowDays: "four weeks"
        case Experiment.defaultWindowDays: "two weeks"
        default: windowDays == 1 ? "one day" : "\(windowDays) days"
        }
    }

    /// The assigned days, as a list somebody can keep.
    ///
    /// Nil for a chosen window, which has no such list. Formatted through the
    /// calendar's own locale rather than a fixed English pattern, because a weekday
    /// name is the one string in this feature the app does not write.
    static func assignedDays(for experiment: Experiment,
                             calendar: Calendar = .current) -> String? {
        guard let assignment = experiment.assignment else { return nil }
        let dates = assignment.assignedDates(startedAt: experiment.startedAt, calendar: calendar)
        guard !dates.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.dateFormat = "EEE d"
        return "Your days: " + dates.map { formatter.string(from: $0) }.joined(separator: ", ") + "."
    }

    /// Whether today carries the change.
    ///
    /// **A drawn window is unusable without this.** The ordinary offer is a standing
    /// instruction somebody can hold in their head for a fortnight; a list of fourteen
    /// dates is not, and an app that draws the days and then expects somebody to keep
    /// the list themselves has made the harder offer and withheld the only thing that
    /// makes it followable. Nil outside the window, so a closed or unstarted one says
    /// nothing rather than something wrong.
    ///
    /// - Parameter now: passed in, never read here. One read of the clock per
    ///   decision is a rule this codebase has already paid for breaking.
    static func today(for experiment: Experiment, on now: Date,
                      calendar: Calendar = .current) -> String? {
        guard let assignment = experiment.assignment,
              let offset = assignment.dayOffset(
                of: now, startedAt: experiment.startedAt,
                windowDays: experiment.windowDays, calendar: calendar)
        else { return nil }
        return assignment.isAssigned(dayOffset: offset)
            ? "Today is one of your days."
            : "Today is not one of your days."
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

    /// What a stopped experiment says for itself.
    ///
    /// Here rather than in the screen that draws it, because this file is where
    /// every experiment sentence lives so that one sweep sees all of them — a string
    /// authored in a feature file is one no sweep can find. Distinct from
    /// `stopTitle`, which is the control that does the stopping: one is a button,
    /// the other is a row in a record, and they are not the same words.
    ///
    /// It is deliberately not a fourth verdict. Nothing was tested, so there is
    /// nothing to report about the change, and the row carries no figures at all.
    static let stoppedStanding = "Stopped"
    static let stoppedReport = "This one was stopped early, so it has no result."

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
    /// The second way to accept the same proposal, and a different offer.
    ///
    /// Beside `startTitle` rather than instead of it: a drawn window is a second kind
    /// and the simpler one stays available, because somebody who will not commit to
    /// specific days should still be able to run the test they were offered.
    static let randomiseTitle = "Pick the days for me"

    /// Every control title, for the sweep.
    static let controlTitles = [startTitle, declineTitle, stopTitle, acknowledgeTitle,
                                randomiseTitle]

    /// The spoken lead-in to the change on a settled card.
    ///
    /// Here rather than in the view body it is read in, for the reason every other
    /// sentence in this feature is here: the guard sweep walks this file, and a string
    /// authored inside a `View` is a sentence no sweep can see. It was the last one.
    static let testedPrefix = "You were testing:"

    // MARK: - Result

    /// What the window produced, in one sentence.
    ///
    /// Each case states where the numbers landed and stops. None of them says the
    /// change was the reason, because a concurrent control over one fortnight does
    /// not reach that and the caveat shown beside this says so.
    static func result(for experiment: Experiment, settlement: Experiment.Settlement) -> String {
        let focus = figure(settlement.focusFigure, outcome: experiment.outcome)
        let baseline = figure(settlement.baselineFigure, outcome: experiment.outcome)

        // A drawn window says what it is allowed to say and nothing more.
        //
        // **"When the days were chosen for you" is the whole upgrade, in words.** A
        // chosen window licenses "this held up when you changed it on purpose", and
        // every sentence in this file was written to that limit. Drawing the days
        // beforehand means the comparison is not between days the person picked, so
        // the claim can name that — and stops exactly there. It is still not "this
        // causes", it is still one person and one month, and the caveat beside it says
        // so.
        //
        // **The labels change with the arms.** `focusLabel` is not used here, and that
        // is deliberate rather than an omission: the assigned arm holds every rated
        // session on a picked day, including the days the change did not happen on, so
        // calling that figure "Morning" would attach a label the number does not
        // carry. "Your picked days" is what the arm actually is.
        if experiment.isRandomised {
            switch settlement.verdict {
            case .heldUp:
                return "Your picked days settled at \(focus) against \(baseline) on the rest. "
                    + "It held up when the days were chosen for you." + dilution(settlement)
            case .didNotHoldUp:
                return "Your picked days settled at \(focus) against \(baseline) on the rest. "
                    + "No difference you could act on." + dilution(settlement)
            case .cannotTell:
                return cannotTell(settlement)
            }
        }

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

    /// How far the window managed to put the two arms apart, when something came
    /// between them.
    ///
    /// **Why a readable verdict says this at all.** A drawn window that clears the
    /// gate has arms that are still ordered the way the draw put them, so "no
    /// difference you could act on" is an honest reading of it — but a window with
    /// four contaminated days measured whatever the change does at less than its full
    /// size, and a reader deciding what to do next is owed that. It is one more
    /// sentence rather than a hedge inside the verdict's own, because the verdict
    /// states what was measured and this states how far apart the month managed to get
    /// the two sets of days. One sentence per fact is this file's register.
    ///
    /// **The same clause on both readable verdicts, deliberately.** Contamination
    /// pulls the arms together, so it can only have made `heldUp` harder to reach —
    /// which is worth knowing beside a result that reached it anyway. Reporting it
    /// only under the null would be disclosing an inconvenience exactly when it was
    /// convenient.
    ///
    /// Empty for a chosen window, which has no unasked days, and for a drawn one
    /// where the change stayed on the days it was asked for.
    private static func dilution(_ settlement: Experiment.Settlement) -> String {
        guard let contamination = settlement.contaminationDays, contamination > 0 else { return "" }
        return " The change also happened on \(contamination) of the "
            + "\(settlement.baselineDays) days it was not picked for, so the two sets of days "
            + "ended up closer together than the draw asked for."
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

        // A drawn window has one more way to be unreadable than a chosen one, and it
        // is the interesting one: the change happened on days it had not been asked
        // for, until there were not enough days left without it to read against.
        //
        // Said as a count of what happened rather than as a reproach. Nobody did
        // anything wrong by putting a block in their morning on a Tuesday, and the
        // sentence that implied they had would be the app blaming somebody for living
        // their life in the middle of its experiment. What it reports is that the
        // month stopped being able to answer the question, which is a fact about the
        // evidence — the same thing `cannotTell` says in every other arm.
        if let contrast = settlement.contrastDays {
            if adherence < floor {
                return "\(floor) days of it would have been enough to read. There were \(adherence)."
            }
            let contamination = settlement.contaminationDays ?? 0
            if contamination > 0 && contrast < floor {
                return "The change happened on \(contamination) of the \(baseline) days it was "
                    + "not picked for. That leaves \(contrast) to read against, "
                    + "where \(floor) would have been enough."
            }
            if contrast < floor {
                return "\(floor) days without it would have been enough to read against. "
                    + "There were \(contrast)."
            }
            // Both sides cleared the floor and the two arms still came out too alike
            // to tell apart: the change was at least as common on the days it was not
            // picked for as on the days it was, or it took the majority of the arm it
            // had been withheld from. `Experiment.armsSeparated` is the rule.
            //
            // **This is the sentence the phase was missing.** Without it this window
            // reported "No difference you could act on", which reads as a statement
            // about the change, when the only honest statement available is about the
            // month. So it says what the two sets of days came out as, in the same
            // register as the contamination sentence above: two counts, and no
            // suggestion that either of them was a mistake.
            if settlement.armsSeparated == false {
                return "The change happened on \(adherence) of the days it was picked for "
                    + "and \(contamination) of the \(baseline) days it was not. "
                    + "Those two sets came out too alike to read one against the other."
            }
            return "This one can no longer be read against your record."
        }

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

    /// A figure, in the unit the thing being measured is actually in.
    ///
    /// **A residual is bpm and a rating is not.** Everything in this file was
    /// written when the only measured outcome was a feeling, where a bare "4.2"
    /// against "3.4" reads correctly because the scale is understood. A residual
    /// experiment settles at "4.2" meaning four and a bit beats above this person's
    /// usual, and printed bare beside a sentence about days it reads as a rating —
    /// a different quantity on a different scale, out by a factor nobody can see.
    ///
    /// The residual is also signed: below usual is a real and different answer from
    /// above it, and dropping the sign would merge them.
    private static func figure(_ value: Double, outcome: Outcome) -> String {
        switch outcome {
        case .feeling, .performance:
            return figure(value)
        case .heartRateResidual:
            let magnitude = String(format: "%.1f", abs(value))
            if abs(value) < 0.05 { return "your usual" }
            return value > 0 ? "\(magnitude) bpm above your usual"
                             : "\(magnitude) bpm below your usual"
        }
    }

    /// One decimal, because the scale has five points and a second decimal would
    /// imply a precision five points do not have.
    private static func figure(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
