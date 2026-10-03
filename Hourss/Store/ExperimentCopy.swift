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
    /// **Shortened on the owner's reading, and the argument survived the cut.** The
    /// first version was forty-eight words in two clauses, the second of which ran
    /// "the only ones that can tell a change that held up from a stretch that was
    /// going well anyway" — true, and the longest way to say it. The owner could not
    /// follow it on device. What had to stay is the mechanism (the app picks, not
    /// you) and the reason (days you did not pick are what separate the two), and
    /// both are still here in two short sentences. "Held up" is now the verdict's
    /// own word, which it was not before, so the ask and the result name the same
    /// outcome.
    static func randomisedAsk(windowDays: Int, assignedDays: Int) -> String {
        "The app picks \(assignedDays) of the next \(windowDays) days, including days you "
            + "would rather not. Days you did not pick are the ones that can tell a change "
            + "that held up from a good stretch."
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
    ///
    /// Internal rather than private since the accept sheet's "how long" needs the
    /// same two words the caveat uses. One spelling of a length, in one place: a
    /// sheet that said "a fortnight" above a caveat saying "two weeks" would be two
    /// vocabularies for one commitment, which is the drift this whole file is built
    /// to stop.
    static func span(_ windowDays: Int) -> String {
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
    /// Says no to the question, not to the app, and says which in the control's own
    /// words.
    ///
    /// **It read "Not this one", and the sentence under it was carrying the label.**
    /// The owner looked at the sheet on device and could not work out what the
    /// control refused until they had read `declineNote` beneath it. That is a label
    /// which has failed: the one control on this screen that cannot be undone is the
    /// last one anybody should have to read a paragraph to understand. "This test"
    /// is the scope and "again" is the permanence, and both are now in the four
    /// words on the control itself.
    ///
    /// **Which is why the note was deleted rather than shortened.** `declineNote`
    /// existed to say two things: that this question will not come back, and that
    /// other proposals still will. The first is now in the title. The second follows
    /// from the title naming *this test* rather than testing — a reader told they
    /// are declining one test does not conclude they have switched the feature off,
    /// and a second sentence saying so was a paragraph spent undoing a reading the
    /// label no longer invites.
    static let declineTitle = "Don't offer this test again"

    /// What a card's own control does now, which is open the sheet rather than start
    /// anything.
    ///
    /// **A separate title because it is a separate act, and the old one had become a
    /// lie.** `startTitle` used to sit on the card and begin a fortnight on one tap.
    /// The card now offers only the reading, and a link still reading "Start this"
    /// that opened a sheet would be the worst of both: a control whose words promise
    /// a commitment and whose behaviour withholds it, so nobody would trust either.
    ///
    /// Deliberately not "Learn more" or "Details". Both are chrome words that say
    /// nothing about what is behind them; this names the question somebody actually
    /// has before agreeing to a fortnight.
    static let openTitle = "See what this involves"

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
                                randomiseTitle, openTitle]

    /// The spoken lead-in to the change on a settled card.
    ///
    /// Here rather than in the view body it is read in, for the reason every other
    /// sentence in this feature is here: the guard sweep walks this file, and a string
    /// authored inside a `View` is a sentence no sweep can see. It was the last one.
    static let testedPrefix = "You were testing:"

    /// The eyebrow over a window in progress.
    ///
    /// Here rather than in the three view bodies that drew it. It was authored in
    /// `ObservationSlotView`, in `InsightDetailView` and — once the accept sheet
    /// needed a confirmation — would have been authored a third time, which is three
    /// chances for one phrase to drift and no sweep able to see any of them.
    static let activeStanding = "You are testing this"

    // MARK: - The accept sheet

    /// Every sentence the accept sheet shows, assembled before anything draws it.
    ///
    /// **Why a value and not a view.** The sheet is the most consequential screen in
    /// the app — it is where somebody agrees to spend a fortnight — and the thing
    /// most likely to go wrong about it is not its layout but its words. A struct is
    /// swept, diffed and asserted against; a `body` can only be looked at. This is
    /// the same split `SlotCopy` makes for the band on Today and for the same
    /// reason.
    ///
    /// **What is authored here and what is carried.** `change`, `premise`, `context`
    /// and `limit` are the proposal's own strings and are reproduced untouched —
    /// word for word what the card showed, because a sheet that rephrased the offer
    /// would mean the thing somebody agreed to was not the thing they were shown.
    /// Everything else is written here, and `authoredStrings` is what the copy sweep
    /// walks.
    ///
    /// **Two marks are described here too, and that is deliberate.** `Part.span` and
    /// `Part.stages` carry the labels printed beside a drawing, not the drawing. The
    /// view owns the geometry and owns none of the words, which is the only way the
    /// sweep can still see every word a reader meets on the one screen that matters
    /// most — a date label authored in a `View` is a label no test can find.
    struct ProposalSheet: Equatable {

        /// One thing a section says, in the order it is read.
        ///
        /// **This replaced a flat `[String]`, and the flat list is what forced the
        /// change.** Every entry used to be a sentence and the view decided how to
        /// set each one by counting: index zero was the answer, the rest were
        /// qualifiers, and a section holding more than two lines had *every* line set
        /// primary, because that was the only way the three verdicts came out equal.
        /// A rule inferred from a count breaks the moment a section gains a line, and
        /// the owner asked for exactly that — sub-headed verdicts, and two marks. So
        /// the register each thing is set in is named here instead of guessed at the
        /// call site.
        ///
        /// It is also the shape the rest of the app takes if this sheet survives its
        /// trial: a section is a heading and a list of parts, and a part knows what
        /// kind of thing it is.
        enum Part: Equatable {
            /// The answer to the section's question.
            case line(String)
            /// A sentence qualifying the answer, set in the quiet register.
            case quiet(String)
            /// A named outcome and the one line under it. The name is set bold so
            /// that the three verdicts can be found without reading their glosses,
            /// which is the whole of what the owner asked for about section 4 — and
            /// the reason this is one case rather than two `line`s, which the view
            /// would have had to tell apart by counting again.
            case titled(String, String)
            /// A length of time, drawn as the stretch it runs over.
            case span(start: String, end: String)
            /// How far a reading got, drawn as the gates it has and has not cleared.
            case stages([Stage])

            /// Everything this part puts on screen or into a readout.
            var strings: [String] {
                switch self {
                case .line(let text), .quiet(let text):
                    return [text]
                case .titled(let title, let detail):
                    return [title, detail]
                // The joining word is here and not in the view, for the reason the
                // whole file exists. Spoken as one phrase because "Today. Sat 17
                // Oct." is two labels read out as two facts, and the fact is the
                // stretch between them.
                case .span(let start, let end):
                    return ["\(start) to \(end)."]
                case .stages(let stages):
                    return stages.map(\.spoken)
                }
            }
        }

        /// One gate a reading either cleared or has not.
        ///
        /// **Why the state is a word as well as a mark.** The drawing tells the two
        /// apart by fill — solid when cleared, an outline when not — which is a shape
        /// distinction and survives greyscale, and the label's own colour reinforces
        /// it. Neither reaches VoiceOver. So the state is a string too, and it is
        /// authored here with every other word on the screen rather than in the view
        /// that speaks it.
        struct Stage: Equatable {
            let label: String
            let cleared: Bool

            var spoken: String { "\(label): \(cleared ? Self.doneWord : Self.pendingWord)." }

            static let doneWord = "done"
            static let pendingWord = "not yet"
        }

        /// The second way to accept, with the paragraph that has to earn it.
        struct Randomised: Equatable {
            let title: String
            let ask: String
        }

        /// One block: a heading and the parts under it, in reading order.
        struct Section: Equatable {
            let heading: String
            let parts: [Part]

            /// Every string in the block, in reading order. For the sweep, and for
            /// the readout below.
            var lines: [String] { parts.flatMap(\.strings) }

            /// What VoiceOver reads for the block.
            ///
            /// Heading first, so the subject arrives before anything else — the rule
            /// `DESIGN.md` records as *Readouts name their subject first*, and the
            /// reason no label here opens with a figure. The marks speak through this
            /// too: a reader who cannot see a drawing still gets its labels and, for
            /// a stage, whether it was cleared.
            var spoken: String { ([heading] + lines).joined(separator: ". ") }
        }

        /// What this rests on, in the card's own words. Stated at the top because a
        /// lead that did not announce itself as a lead would be a claim.
        let standing: String

        /// Section 1. The change, and nothing with it — this is the sentence that
        /// gets set large, and the only part there is anything to do about.
        let whatYouWouldDo: Section
        /// Section 2. What the app saw, with its numbers and its day count.
        let whyThisOne: Section
        /// Section 3. Which gates the reading cleared, and what the uncleared one
        /// means for this standing.
        let howItDecided: Section
        /// Section 4. All three verdicts, in the words the result will use.
        let whatYouGet: Section

        let howLong: Section
        /// Nil for the one outcome whose measurement the change already names. See
        /// `ExperimentCopy.whatIsMeasured(_:)`.
        let whatIsMeasured: Section?
        /// The hypothesis's own caveat, carried.
        let limit: Section

        let startTitle: String
        /// Nil where the days cannot be drawn.
        let randomised: Randomised?
        let declineTitle: String

        /// The proposal's own sentences, reproduced untouched.
        ///
        /// Named so that `authoredStrings` can subtract them. They are swept where
        /// they are built — by `ExperimentDesignTests` and `ExperimentStarterTests` —
        /// and sweeping them again here would make this file answerable for wording
        /// it only carries.
        let carried: [String]

        /// The sections, in the order they are read. A sheet that answered them in
        /// any other order would be asking somebody to agree before saying what they
        /// get.
        var orderedSections: [Section] {
            [whatYouWouldDo, whyThisOne, howItDecided, whatYouGet, howLong]
                + [whatIsMeasured].compactMap { $0 } + [limit]
        }

        /// The words on the three controls.
        var controlStrings: [String] {
            [startTitle, declineTitle] + (randomised.map { [$0.title, $0.ask] } ?? [])
        }

        /// Everything that reaches the screen, carried sentences included.
        var allStrings: [String] {
            [standing] + orderedSections.flatMap(\.lines) + controlStrings
        }

        /// Strings this file is answerable for.
        ///
        /// **Subtraction rather than a list, and the old list is why.** Every field
        /// used to be appended by hand, one `append` per field, with a comment
        /// recording that the chained `+` version had made Swift's type checker give
        /// up. It also had to be edited every time a section gained a line — and a
        /// sweep somebody has to remember to extend is a sweep with a hole in it,
        /// which is precisely what this file exists to prevent. Carried sentences are
        /// the only ones this file does not own, so naming those and taking them out
        /// is the whole rule.
        var authoredStrings: [String] {
            let borrowed = Set(carried)
            return allStrings.filter { !borrowed.contains($0) }
        }
    }

    /// The sheet for one proposal.
    ///
    /// - Parameter windowDays: how long the ordinary offer runs, which is the one
    ///   the start control takes. The drawn option states its own length inside
    ///   `randomisedAsk`, so nothing here has to hedge between two numbers.
    /// - Parameter now: the day the window would start, which is the left end of the
    ///   span the sheet draws. Passed in and never read here, because one read of the
    ///   clock per decision is a rule this codebase has already paid for breaking:
    ///   the sheet holds it so the drawn span cannot shift under a redraw.
    static func sheet(for proposal: ExperimentDesign.Proposal,
                      windowDays: Int = Experiment.defaultWindowDays,
                      now: Date = .now,
                      calendar: Calendar = .current) -> ProposalSheet {
        // The premise, then — quietly, and only for a starter — the Health reading it
        // was built from. Same order as the card, for the same reason: a Health
        // sentence directly under the change reads as the reason for it, and the
        // sentence denying exactly that has to come between them.
        var why: [ProposalSheet.Part] = [.line(proposal.premise)]
        if let context = proposal.context { why.append(.quiet(context)) }

        return ProposalSheet(
            standing: eyebrow(for: proposal.standing),
            whatYouWouldDo: .init(heading: whatYouWouldDoHeading,
                                  parts: [.line(proposal.change)]),
            whyThisOne: .init(heading: whyThisOneHeading, parts: why),
            howItDecided: .init(heading: howItDecidedHeading,
                                parts: howItDecidedParts(proposal.standing)),
            whatYouGet: .init(heading: whatYouGetHeading, parts: whatYouGetParts),
            howLong: .init(heading: howLongHeading,
                           parts: [.line(howLong(windowDays: windowDays)),
                                   .span(start: spanStart,
                                         end: spanEnd(windowDays: windowDays,
                                                      from: now, calendar: calendar))]),
            whatIsMeasured: whatIsMeasured(proposal.outcome).map {
                .init(heading: whatIsMeasuredHeading, parts: [.line($0)])
            },
            limit: .init(heading: limitHeading, parts: [.line(proposal.caveat)]),
            startTitle: startTitle,
            randomised: proposal.randomisedAsk.map {
                .init(title: randomiseTitle, ask: $0)
            },
            declineTitle: declineTitle,
            carried: [proposal.change, proposal.premise, proposal.caveat]
                + [proposal.context].compactMap { $0 }
        )
    }

    // MARK: Sheet headings

    /// Four questions and three terms, each phrased as the question somebody has
    /// rather than as a label for a field.
    ///
    /// **The order is the design and it is not interchangeable.** A research consent
    /// flow reads what this is, what you will do, how long, what is measured, then
    /// agree — and it feels significant because the sequence puts the commitment
    /// last. "What you get at the end" sits above the terms for the same reason: the
    /// three verdicts are the part a reader has to have met *before* tapping, since
    /// the whole purpose of naming them up front is that a null result arriving in a
    /// fortnight is not a surprise.
    ///
    /// **These are the strings that went orange.** They are the only headings on the
    /// sheet, there are seven of them, and from the owner's reading on device they
    /// are now the one thing the eye can use to find its place — see *Orange has a
    /// second job on one screen* in `DESIGN.md`. Nothing about the words changed:
    /// the colour replaced the rule that used to sit above each of them.
    static let whatYouWouldDoHeading = "What you would do"
    static let whyThisOneHeading = "Why this one"
    static let howItDecidedHeading = "How it decided"
    static let whatYouGetHeading = "What you get at the end"
    static let howLongHeading = "How long"
    static let whatIsMeasuredHeading = "What is measured"
    /// The app's existing word for a caveat, reused rather than renamed. Today's
    /// band, the insight detail screen and the history list all head a limit with
    /// this, and inventing "The limit" for the sheet would be a second name for the
    /// one thing the reader is meant to recognise across four screens.
    static let limitHeading = "Bear in mind"

    // MARK: How it decided

    /// What was compared, as the two gates a reading either cleared or has not.
    ///
    /// **This was three paragraphs and is now two labels and a mark.** Each standing
    /// used to get its own forty-word sentence, all three opening with the same
    /// clause about comparing this group against the rest of your own record. The
    /// owner asked for the section to be drawn rather than written, and the honest
    /// content turned out to be a procedure: a reading is compared against this
    /// person's own record, and then — only for a confirmed one — it is checked
    /// against every other pattern in that record and has to still be standing.
    /// Two gates, in order, each either cleared or not.
    ///
    /// **Why this is the shape and not a two-sided comparison.** The obvious drawing
    /// for "what was compared against what" is two labelled sides, and `ComparisonMark`
    /// already draws one. It is the wrong mark here twice over: it needs two *values*
    /// on a shared scale, and the only values available are the premise's own two
    /// figures, which the section above already prints — the "no figure in the well"
    /// rule in `DESIGN.md` is about exactly that. And a starter has no figures at all,
    /// so the mark would have had to be absent for the one standing that most needs
    /// the section to say something.
    ///
    /// **It is honest for a starter, which was the hard case.** A starter has cleared
    /// neither gate, so the mark draws two empty outlines and nothing else — it draws
    /// nothing, and the note under it says so in words. Two unfilled boxes beside the
    /// labels of the two things that have not happened is the most a starter can
    /// truthfully be shown.
    static func howItDecidedParts(_ standing: ExperimentDesign.Standing)
        -> [ProposalSheet.Part] {
        let stages = [
            // Cleared by anything measured. A lead has six rated days a side of a
            // real split; only a starter has had nothing compared at all.
            ProposalSheet.Stage(label: comparedStage, cleared: standing != .starter),
            // The correction, and only a confirmed claim has been through it.
            ProposalSheet.Stage(label: correctedStage, cleared: standing == .confirmed),
        ]
        guard let note = howItDecidedNote(standing) else { return [.stages(stages)] }
        return [.stages(stages), .quiet(note)]
    }

    /// The first gate, carrying the one clause that could not be dropped.
    ///
    /// "And nobody else's" is the standing rule *A person is only ever measured
    /// against their own history*, said on the screen where somebody is deciding
    /// whether to trust the reading. It was in all three of the sentences this
    /// replaced and it is in the label now.
    static let comparedStage = "Compared with your own record, and nobody else's"

    /// The second gate, said as what it does rather than as what it is.
    ///
    /// **No maths, and that is a constraint rather than a simplification.** The
    /// honest thing to say about a bootstrap interval over day-clustered resamples is
    /// not a smaller version of the arithmetic — it is what the arithmetic was for.
    static let correctedStage = "Still standing after every other pattern was checked"

    /// What the uncleared gate means, for the standings that have one.
    ///
    /// Nil for a confirmed claim, which has cleared both: two filled marks beside
    /// their own labels is the complete statement, and a sentence restating it would
    /// be the section saying the same thing twice in two registers.
    static func howItDecidedNote(_ standing: ExperimentDesign.Standing) -> String? {
        switch standing {
        case .confirmed:
            return nil
        case .lead:
            // "Leans" rather than "shows", for the reason the lead premise says "has
            // read higher" and never "is better".
            return "It leans one way, and has not been watched long enough to be more "
                + "than a lean."
        case .starter:
            // Says outright that nothing was measured. Deliberately not "so this is a
            // place to start", which the sheet's own title already says eight
            // sections higher and which would be the same claim twice on one screen.
            return "Nothing you have logged has been measured against anything yet."
        }
    }

    // MARK: What you get at the end

    /// All three verdicts, named before anybody agrees to anything.
    ///
    /// **This section is the reason the sheet exists.** Everything else here is an
    /// honest description of an offer; this is the part nobody else ships. Saying
    /// beforehand that a fortnight can come back with no difference does two things
    /// that cannot be done afterwards: it makes a result that holds up feel earned,
    /// and it stops a null reading as the app having failed to work. A reader who
    /// meets "It did not hold up" for the first time on day fifteen has every reason
    /// to think something broke.
    ///
    /// **Three rules it obeys.** The verdicts are named by `verdictTitle`, so they
    /// are the exact words the result will use and cannot drift from it. None of the
    /// three is softened, hedged or called unlikely — the closing line says the null
    /// is what makes the test worth running, which is the strongest true thing
    /// available and the opposite of an apology. And they are in the order the result
    /// screen puts them, so the one that held up is not the one at the bottom.
    ///
    /// **Shortened and formatted, and what that cost.** It was five sentences of flat
    /// body text, ninety-five words, every line set at the same weight because the
    /// view could only tell "a section with more than two lines" to set all of them
    /// primary. The owner could not read it. It is now a preamble, three named rows
    /// and a closing line — sixty words, with each verdict's name set bold above its
    /// own gloss, so the three can be counted without being read. Two clauses went:
    /// "and which one is the whole point of running it" from the preamble, which the
    /// closing line says better, and "and you will be shown whichever one it is",
    /// which "all three are results" already carries. Nothing that makes a null
    /// sound unlikely was added, and nothing that makes one sound ordinary was taken
    /// away.
    ///
    /// The glosses name no direction and no figure. `heldUp` is "settled apart"
    /// rather than "read higher" because a residual window's better side is resolved
    /// per person, and a sheet that promised "higher" would be wrong for half of
    /// them.
    static var whatYouGetParts: [ProposalSheet.Part] {
        [
            .line(verdictPreamble),
            .titled(verdictTitle(.heldUp), heldUpGloss),
            .titled(verdictTitle(.didNotHoldUp), didNotHoldUpGloss),
            .titled(verdictTitle(.cannotTell), cannotTellGloss),
            .quiet(verdictClosing),
        ]
    }

    static let verdictPreamble = "One of these three."
    static let heldUpGloss = "The days with the change settled far enough apart from "
        + "the rest to read."
    static let didNotHoldUpGloss = "The two sets of days settled too close together "
        + "to tell apart."
    static let cannotTellGloss = "Too few days carried the change, or too few went "
        + "without it."
    /// The line that stops a null reading as a fault. Not shortened past the clause
    /// that does the work: "a test that could only come back the first way would not
    /// be worth running" is the argument, and without it "all three are results" is
    /// a disclaimer rather than a reason.
    static let verdictClosing = "All three are results. A test that could only come back "
        + "the first way would not be worth running."

    /// Every string section 4 shows, for the tests that sweep it.
    static var whatYouGetLines: [String] { whatYouGetParts.flatMap(\.strings) }

    // MARK: The terms

    /// How long the ordinary offer runs, as the length and nothing else.
    ///
    /// **It used to end ", from the day you start", and the span mark says that
    /// now.** The two ends of the drawn span are labelled `spanStart` and the date
    /// the window would close, which is the same clause as a picture and also the
    /// fact the sentence was withholding: a reader who wanted to know when this
    /// finishes had to do the arithmetic themselves.
    ///
    /// No full stop. It is a quantity set on its own line above its own mark, not a
    /// sentence, and `Section.spoken` joins it to its neighbours with one anyway.
    static func howLong(windowDays: Int = Experiment.defaultWindowDays) -> String {
        let length = span(windowDays)
        return "\(length.prefix(1).uppercased())\(length.dropFirst())"
    }

    /// The near end of the window.
    ///
    /// "Today" rather than a date, because the far end is the one somebody cannot
    /// work out and the near one is the day they are holding the phone on. It is
    /// accurate the instant it is read and is a day out if the sheet is left open
    /// overnight and then accepted — which is why `started(_:)` restates the closing
    /// date from the window's real start, and why that string and this one are
    /// formatted by one function.
    static let spanStart = "Today"

    /// The far end: the day a window started now would close.
    static func spanEnd(windowDays: Int = Experiment.defaultWindowDays,
                        from now: Date = .now,
                        calendar: Calendar = .current) -> String {
        let end = calendar.date(byAdding: .day, value: windowDays, to: now) ?? now
        return closingDate(end, calendar: calendar)
    }

    /// One spelling of a closing date, so the sheet's prediction and the
    /// confirmation's statement cannot come out as two strings for one day.
    ///
    /// "EEE d MMM" where `assignedDays` uses "EEE d". The drawn days are all inside
    /// the window and read as a short list, where a bare "1" is unambiguous in
    /// context; a closing date is up to four weeks out and can easily fall in the
    /// next month, where it is not.
    ///
    /// Formatted through the calendar's own locale rather than a fixed English
    /// pattern, because a weekday name is the one string in this feature the app does
    /// not write.
    static func closingDate(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }

    /// What the window reads, and on which days.
    ///
    /// **Nil for a residual, and that is the no-second-wording rule biting.** The
    /// change for a residual window already ends "This one is read from your heart
    /// rate, so it needs no ratings" — it is said there because it is the one offer
    /// in the app that asks *less* of somebody than the others, which belongs beside
    /// the ask. A second sentence here saying the same thing in different words is
    /// exactly how a claim and its card drift apart, and a second sentence saying it
    /// in the same words is a paragraph repeated on one screen. So the section is
    /// absent and the change carries it.
    ///
    /// The two rated outcomes name the days as well as the measurement, because
    /// "how each session felt" on its own does not say that the days *without* the
    /// change are measured too — and a reader who thinks only the changed days count
    /// has misunderstood what they are agreeing to.
    static func whatIsMeasured(_ outcome: Outcome) -> String? {
        switch outcome {
        case .feeling:
            return "How each of your sessions felt, on the days the change happened and "
                + "on the days it did not."
        case .performance:
            return "How each of your sessions went, on the days the change happened and "
                + "on the days it did not."
        case .heartRateResidual:
            return nil
        }
    }

    // MARK: After agreeing

    /// What was just started, when it closes, and the drawn days if there are any.
    ///
    /// **A confirmation rather than a dismissal, because something irreversible
    /// just happened.** Accepting fixes the hypothesis, the arms and the window, and
    /// only one can run at a time. A sheet that closed silently would leave somebody
    /// on Today wondering whether the tap registered, and the one place a drawn
    /// window's day list can be read for the first time is the moment it is drawn.
    ///
    /// - Parameter calendar: passed through, so the closing date and the day list are
    ///   formatted in the same calendar the draw was made in.
    static func started(_ experiment: Experiment, calendar: Calendar = .current) -> String {
        // Through `closingDate` rather than a formatter of its own, so this date and
        // the far end of the span the sheet drew a moment ago are one string for one
        // day. They were two formatters with the same pattern, which is two places
        // for a pattern to change.
        let closes = closingDate(experiment.endsAt(calendar: calendar), calendar: calendar)
        return "This runs for \(span(experiment.windowDays)) and closes on \(closes)."
    }

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
