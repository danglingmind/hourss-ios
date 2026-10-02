import SwiftUI

/// The single band on Today, resolved and then rendered.
///
/// Three things live here and they are deliberately separable. `ObservationSlot`
/// decides *which* of the five contents owns the slot, from a handful of values
/// and nothing else. `SlotCopy` turns that decision into the exact strings that
/// will appear, still without a view. `ObservationSlotView` draws them.
///
/// The split is the point. The precedence in PRD A.11 is a business rule, and the
/// copy bounds in BR-28 and BR-29 are business rules; neither can be asserted
/// against a `body` that only exists once a screen has been mounted. Both are
/// values here, so both are testable.

// MARK: - The decision

/// Everything the precedence table reads, and nothing else.
///
/// Small and `Equatable` on purpose: the five-row table is the highest-risk thing
/// on this screen and a test of it should be able to state a whole situation in
/// one literal.
struct SlotState: Equatable {
    var tier: Tier = .free

    /// Distinct calendar days carrying at least one rated session — the unit the
    /// engine counts in. Six sessions on one Tuesday are one day of evidence.
    var ratedDayCount: Int = 0

    /// A session logged today that carries no feeling score.
    var unratedSessionId: UUID?

    /// How many recommendations the layer would produce for this person, run
    /// regardless of entitlement. The prompt names this number, so it has to be
    /// the count of recommendations rather than of surviving claims.
    var recommendationCount: Int = 0

    /// Identity of the one the slot would show. Always the insight's own id.
    var leadRecommendationId: UUID?

    /// Strongest visible insight, where there is one.
    var leadInsightId: UUID?

    /// A finished test whose result has not been seen. Claims the slot once.
    var settledExperimentId: UUID?

    /// A fortnight in progress.
    var activeExperimentId: UUID?

    /// Identity of the proposal the slot would offer. Always the insight's own id,
    /// as `leadRecommendationId` is, so a card and the claim it rests on share one.
    var proposalId: UUID?

    /// Whether that proposal rests on a confirmed claim rather than a lead.
    ///
    /// Carried separately rather than inferred from the tier, because the entitlement
    /// question and the standing question are different: a lead is free and reaches
    /// everybody, a confirmed one is what membership buys. Defaulting to false means
    /// a state literal that says nothing about standing describes the free case,
    /// which is the common one.
    var proposalRequiresMembership: Bool = false

    var meetsEvidenceFloor: Bool { ratedDayCount >= EvidenceFloor.days }

    /// Whether the proposal, if there is one, may be shown to this person.
    var canSeeProposal: Bool {
        proposalId != nil && (!proposalRequiresMembership || tier.isEntitled)
    }
}

enum ObservationSlot {

    /// The five-row table from PRD A.11, in order. The first that applies owns
    /// the slot.
    ///
    /// Two departures from a literal reading of that table, both forced by rules
    /// that outrank it:
    ///
    /// The upgrade prompt is additionally gated on the evidence floor. The table
    /// does not gate it, but a comparison split within a day can clear the
    /// engine's six-days-a-side minimum on as few as six distinct days, so a
    /// recommendation *can* exist below twelve — and BR-29 and the acceptance
    /// criterion "no pitch below the floor" both say a member below the floor
    /// sees no membership wording anywhere on Today. Pitching membership to
    /// somebody who is still watching a progress mark is the mis-sell the rule
    /// exists to prevent, so the floor wins.
    ///
    /// Row 1 is *not* gated the same way. Showing a paying member a real
    /// recommendation earlier than the mark implied is the pleasant half of the
    /// asymmetry A.11 names; withholding what they already paid for, to keep a
    /// progress bar tidy, is not.
    static func content(for state: SlotState) -> SlotContent {
        // A finished test first, above everything including the rating ask. It is
        // the most valuable thing this app can hold and it claims the slot exactly
        // once, so the cost of putting it here is one screen per experiment.
        if let id = state.settledExperimentId {
            return .settledExperiment(id: id)
        }
        // Then a fortnight in progress. Nothing below this is more relevant to
        // somebody mid-window than the window itself.
        if let id = state.activeExperimentId {
            return .activeExperiment(id: id)
        }
        // A proposal outranks a recommendation, which is the whole point: a
        // recommendation restates what held up, a proposal asks for one change and
        // measures it.
        if state.canSeeProposal, let id = state.proposalId {
            return .experimentProposal(id: id)
        }
        if state.tier.isEntitled, let id = state.leadRecommendationId, state.recommendationCount > 0 {
            return .recommendation(id: id)
        }
        if let id = state.unratedSessionId {
            return .unfinishedReflection(sessionId: id)
        }
        if !state.tier.isEntitled, state.meetsEvidenceFloor, state.recommendationCount > 0 {
            return .upgradePrompt(count: state.recommendationCount)
        }
        if let id = state.leadInsightId {
            return .leadObservation(id: id)
        }
        // Row 5 in both of its forms: the mark while the floor is unmet, and the
        // engine's own answer once it is met and nothing has stood out.
        return state.meetsEvidenceFloor ? .stillLooking : .evidenceProgress(days: state.ratedDayCount)
    }

    /// The rating a recommendation pushed out of the slot.
    ///
    /// A.11 records the collision and leaves it to be reconciled here: a
    /// recommendation outranks the unfinished-reflection ask, and on Today that
    /// ask is the only route to rating a session logged earlier in the day. The
    /// collision is not theoretical, because a recommendation persists between
    /// recomputes — so a member could go a week with the ask never surfacing.
    ///
    /// Resolved without touching the precedence table: the recommendation keeps
    /// the slot and carries the ask beneath its caveat. Nothing is displaced,
    /// only stacked. Every other content either *is* the ask or has not displaced
    /// one, so this is nil for all of them.
    ///
    /// Every experiment card keeps the slot the same way and for the same reason.
    /// The active card has the strongest claim to carrying the ask rather than
    /// displacing it: the rating being asked for is what the running fortnight is
    /// measured with, so the two are about the same thing.
    /// Whether a content is drawn as a filled block rather than as a ruled section.
    ///
    /// **A value rather than a computed property on the view, for the reason the
    /// rest of this file is split that way.** "Which states are emphatic" is a
    /// design rule, and a design rule asserted against a `body` can only be asserted
    /// by looking at it. Here a test can state the whole rule in one line — exactly
    /// two of the seven states are filled, and the one `content` the slot resolves
    /// to means it can never draw both.
    static func isCarded(_ content: SlotContent) -> Bool {
        switch content {
        // The two ends of a test. One is the only card somebody waited a fortnight
        // for; the other is the decision without which the first never happens.
        case .settledExperiment, .experimentProposal:
            return true
        // A running window is deliberately not filled, and it is the interesting
        // exclusion. It is on screen every day for two to four weeks, which is the
        // definition of routine, and `roomAbove`'s own argument applies in reverse:
        // a card that is emphatic for twenty-eight days running has taught the eye
        // to stop seeing the fill, and would take the two rare cards down with it.
        case .activeExperiment, .recommendation, .unfinishedReflection, .upgradePrompt,
             .leadObservation, .evidenceProgress, .stillLooking, .none:
            return false
        }
    }

    static func displacedReflection(for state: SlotState) -> UUID? {
        switch content(for: state) {
        case .recommendation, .settledExperiment, .activeExperiment, .experimentProposal:
            return state.unratedSessionId
        case .unfinishedReflection, .upgradePrompt, .leadObservation,
             .evidenceProgress, .stillLooking, .none:
            return nil
        }
    }
}

// MARK: - The words

/// Fills a slot band, or leaves it exactly as it was.
///
/// A modifier rather than a branch in `body` so that the ordinary path keeps the
/// identical view tree it had before — a conditional wrapper around a whole band
/// changes identity, and SwiftUI then rebuilds it from scratch on every transition
/// between two uncarded states.
private struct SlotSurface: ViewModifier {
    let carded: Bool

    func body(content: Content) -> some View {
        if carded {
            content
                .padding(Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .blockSurface(Color.forest)
                .surfaceContent(.forest)
        } else {
            content
        }
    }
}

/// One rendered string, with enough about it to draw it and to sweep it.
struct SlotLine: Equatable {
    /// How loudly it is set, which is also its place in the reading order.
    enum Emphasis { case lead, body, support }

    /// Whether this file wrote the string or the engine handed it over.
    ///
    /// The copy sweep runs over the authored half. A registry caveat reading
    /// "Time of day travels with whatever you tend to schedule then" is the
    /// registry's sentence to answer for, and sweeping it here would only teach
    /// somebody to weaken the sweep.
    enum Origin { case authored, carried }

    var text: String
    var emphasis: Emphasis
    var origin: Origin
}

/// The ask a recommendation stacked beneath itself rather than displacing.
struct SlotAsk: Equatable {
    var sessionId: UUID
    var line: String
    var action: String
}

/// Exactly what the slot will render, before anything renders it.
struct SlotCopy: Equatable {
    var eyebrow: String = ""
    var lines: [SlotLine] = []
    /// The claim's own limit, carried from the insight a recommendation rests on.
    var caveat: String?
    /// Title of the one link a state may offer.
    var action: String?
    var ask: SlotAsk?
    /// What VoiceOver reads for the band as a whole.
    var accessibilityLabel: String = ""

    /// Strings this file is responsible for.
    var authoredStrings: [String] {
        [eyebrow] + lines.filter { $0.origin == .authored }.map(\.text) + [action].compactMap { $0 }
            + [ask?.line, ask?.action].compactMap { $0 }
    }

    /// Everything that reaches a screen, carried strings included.
    var allStrings: [String] {
        [eyebrow] + lines.map(\.text) + [caveat, action, ask?.line, ask?.action].compactMap { $0 }
    }
}

extension ObservationSlot {

    /// The copy for one content, given whatever that content needs to name.
    ///
    /// Everything the caller passes is optional because most states need none of
    /// it, and a state handed nothing still produces a whole, sayable band rather
    /// than a sentence with a hole in it.
    static func copy(
        for content: SlotContent,
        unratedActivityName: String? = nil,
        insight: Insight? = nil,
        recommendation: Recommendation? = nil,
        proposal: ExperimentDesign.Proposal? = nil,
        experiment: Experiment? = nil,
        reading: ExperimentOutcome.Reading? = nil,
        daysRemaining: Int = 0,
        /// Passed in, never read twice. The active card asks whether *today* carries
        /// the change, and a second clock read inside the copy layer is the shape of
        /// a bug this codebase has already shipped once.
        now: Date = Date(),
        displacedActivityName: String? = nil,
        displacedSessionId: UUID? = nil
    ) -> SlotCopy {
        switch content {
        case .settledExperiment:
            return settledCopy(experiment,
                               displacedActivityName: displacedActivityName,
                               displacedSessionId: displacedSessionId)

        case .activeExperiment:
            return activeCopy(experiment, reading: reading, daysRemaining: daysRemaining,
                              now: now,
                              displacedActivityName: displacedActivityName,
                              displacedSessionId: displacedSessionId)

        case .experimentProposal:
            return proposalCopy(proposal,
                                displacedActivityName: displacedActivityName,
                                displacedSessionId: displacedSessionId)

        case .recommendation:
            return recommendationCopy(
                recommendation,
                displacedActivityName: displacedActivityName,
                displacedSessionId: displacedSessionId
            )

        case let .unfinishedReflection(sessionId):
            return reflectionCopy(activityName: unratedActivityName, sessionId: sessionId)

        case let .upgradePrompt(count):
            return promptCopy(count: count)

        case .leadObservation:
            return observationCopy(insight)

        case let .evidenceProgress(days):
            return progressCopy(days: days)

        case .stillLooking:
            return stillLookingCopy()

        case .none:
            return SlotCopy()
        }
    }

    // MARK: Recommendation

    /// Its one action, the claim it rests on, its evidence line, and its caveat —
    /// the four things A.11 says a recommendation in this slot carries.
    ///
    /// Every one of them is carried rather than authored. The engine already
    /// rewrote its action strings out of the free tier's voice; restating any of
    /// them here would put the paid line's wording in two places and let them
    /// drift apart.
    private static func recommendationCopy(
        _ recommendation: Recommendation?,
        displacedActivityName: String?,
        displacedSessionId: UUID?
    ) -> SlotCopy {
        guard let recommendation else { return SlotCopy() }

        var copy = SlotCopy(
            eyebrow: "What's held up",
            lines: [
                SlotLine(text: recommendation.action, emphasis: .lead, origin: .carried),
                SlotLine(text: recommendation.claim, emphasis: .body, origin: .carried),
                SlotLine(text: recommendation.evidence, emphasis: .support, origin: .carried),
            ],
            caveat: recommendation.caveat
        )

        var spoken = "\(recommendation.action) \(recommendation.claim) "
            + "\(recommendation.evidence). Bear in mind: \(recommendation.caveat)"

        if let displacedSessionId, let name = displacedActivityName {
            let line = askLine(activityName: name)
            copy.ask = SlotAsk(sessionId: displacedSessionId, line: line, action: askAction)
            spoken += ". \(line)"
        }

        copy.accessibilityLabel = spoken
        return copy
    }

    // MARK: Experiments

    /// Attaches the displaced rating ask, which every card that outranks it carries.
    ///
    /// Factored out rather than repeated four times: the three experiment cards and
    /// the recommendation all keep the slot the same way, and a fourth copy of this
    /// would be a fourth place for the spoken label and the ask to fall out of step.
    private static func carrying(
        _ copy: SlotCopy, spoken: String,
        displacedActivityName: String?, displacedSessionId: UUID?
    ) -> SlotCopy {
        var copy = copy
        var spoken = spoken
        if let displacedSessionId, let name = displacedActivityName {
            let line = askLine(activityName: name)
            copy.ask = SlotAsk(sessionId: displacedSessionId, line: line, action: askAction)
            spoken += ". \(line)"
        }
        copy.accessibilityLabel = spoken
        return copy
    }

    /// Something to test.
    ///
    /// The change leads, because it is the only part the reader has to do anything
    /// about. The premise sits under it as the reason, and both are carried from
    /// `ExperimentCopy` rather than restated — the proposal somebody accepts has to
    /// be word for word the proposal they were shown, and a second phrasing here
    /// would be two versions of one offer.
    private static func proposalCopy(
        _ proposal: ExperimentDesign.Proposal?,
        displacedActivityName: String?, displacedSessionId: UUID?
    ) -> SlotCopy {
        guard let proposal else { return SlotCopy() }

        // The standing, said plainly. A lead that did not announce itself as a lead
        // would be a claim, and the honest label is the only thing between the two.
        // Three words for three standings — a starter borrowing the lead's used to
        // be the one place this card said more than it knew.
        let eyebrow = ExperimentCopy.eyebrow(for: proposal.standing)

        // Change, then what is not known, then — quietly — the reading it was built
        // from. The order is the whole of the fix for a starter: joined into one
        // sentence with the Health reading first, "your sleep reads 48m shorter on
        // Tuesdays" sat directly beneath "put one block in your morning" and the two
        // read as claim and reason. What sits under the change now is the sentence
        // that denies exactly that, and the reading drops to the register this app
        // uses for metadata, where it says the app has their history rather than
        // offering itself as grounds.
        var lines = [
            SlotLine(text: proposal.change, emphasis: .lead, origin: .carried),
            SlotLine(text: proposal.premise, emphasis: .body, origin: .carried),
        ]
        if let context = proposal.context {
            lines.append(SlotLine(text: context, emphasis: .support, origin: .carried))
        }

        // The card's one control opens the sheet; it no longer starts anything. A
        // link reading "Start this" that opened a reading screen would be a control
        // whose words promise a commitment and whose behaviour withholds it, so the
        // title changed with the behaviour — see `ExperimentCopy.openTitle`.
        let copy = SlotCopy(
            eyebrow: eyebrow,
            lines: lines,
            caveat: proposal.caveat,
            action: ExperimentCopy.openTitle
        )
        // Spoken in reading order, so a screen reader meets the denial before the
        // reading for the same reason the eye does.
        return carrying(copy,
                        spoken: "\(eyebrow). \(proposal.change) \(proposal.premise) "
                            + (proposal.context.map { "\($0) " } ?? "")
                            + "Bear in mind: \(proposal.caveat)",
                        displacedActivityName: displacedActivityName,
                        displacedSessionId: displacedSessionId)
    }


    /// A fortnight in progress.
    ///
    /// **Adherence as a count, never as a streak.** It says how many days carried
    /// the change, which is a fact about what happened, and never frames that number
    /// as something to protect. `RecordFacts` records the same argument at length.
    ///
    /// **The remaining days avoid the words the sweep bans**, and the ban is right
    /// even though a chosen fortnight is not a forecast: "days left" reads as a
    /// deadline whichever state it appears in, and a deadline is the shape that turns
    /// a count into something to defend.
    private static func activeCopy(
        _ experiment: Experiment?, reading: ExperimentOutcome.Reading?, daysRemaining: Int,
        now: Date,
        displacedActivityName: String?, displacedSessionId: UUID?
    ) -> SlotCopy {
        guard let experiment else { return SlotCopy() }

        let days = reading?.adherenceDays ?? 0
        let logged = days == 1
            ? "One day of it so far."
            : "\(spelled(days).capitalizedFirst) days of it so far."
        // "This test", not "this fortnight". A drawn window is twenty-eight days, so
        // naming a fortnight was simply false for half of what the app can now
        // offer — and deriving the word from `windowDays` would mean the card
        // teaching two vocabularies for one thing. The length is not what the line
        // is for; the count is.
        let remaining = daysRemaining == 0
            ? "This test closes today."
            : daysRemaining == 1
                ? "One more day of this test."
                : "\(spelled(daysRemaining).capitalizedFirst) more days of this test."

        // Whether today carries the change, then the list it came from. A standing
        // instruction fits in somebody's head for a fortnight; fourteen drawn dates
        // do not, so an app that picks the days and then leaves somebody to keep
        // the list has made the harder offer and withheld the thing that makes it
        // followable. Both are nil for a chosen window, which has no such list.
        var lines = [
            SlotLine(text: experiment.change, emphasis: .lead, origin: .carried),
        ]
        if let todayLine = ExperimentCopy.today(for: experiment, on: now) {
            lines.append(SlotLine(text: todayLine, emphasis: .body, origin: .carried))
        }
        lines.append(SlotLine(text: logged, emphasis: .body, origin: .authored))
        lines.append(SlotLine(text: remaining, emphasis: .support, origin: .authored))
        if let days = ExperimentCopy.assignedDays(for: experiment) {
            lines.append(SlotLine(text: days, emphasis: .support, origin: .carried))
        }

        let copy = SlotCopy(
            eyebrow: ExperimentCopy.activeStanding,
            lines: lines,
            action: ExperimentCopy.stopTitle
        )
        return carrying(copy,
                        spoken: "\(ExperimentCopy.activeStanding). \(experiment.change) "
                            + (ExperimentCopy.today(for: experiment, on: now).map { "\($0) " } ?? "")
                            + "\(logged) \(remaining)",
                        displacedActivityName: displacedActivityName,
                        displacedSessionId: displacedSessionId)
    }

    /// A finished test.
    ///
    /// The verdict is the eyebrow and the figures lead, so a reader who looks once
    /// gets the answer. "It did not hold up" is set exactly as loudly as "It held
    /// up": an app whose tests always succeed is not running tests, and presenting
    /// the null result quietly would be the first step to not reporting it.
    private static func settledCopy(
        _ experiment: Experiment?,
        displacedActivityName: String?, displacedSessionId: UUID?
    ) -> SlotCopy {
        guard let experiment, let settlement = experiment.settlement else { return SlotCopy() }

        let eyebrow = ExperimentCopy.verdictTitle(settlement.verdict)
        let result = ExperimentCopy.result(for: experiment, settlement: settlement)

        // A caveat belongs with a result that says something held up. There is
        // nothing to qualify about a window that could not be read, and attaching
        // one there would imply a finding that was never made.
        var copy = SlotCopy(
            eyebrow: eyebrow,
            lines: [
                SlotLine(text: result, emphasis: .lead, origin: .carried),
                // Body rather than support. `support` is 11pt mono, which
                // `HealthFactRow` names as the register this app uses for metadata
                // and not for prose — and this is a sentence asking somebody to do
                // something. It reads as a caption of the result above it rather
                // than as the thing that was tested.
                SlotLine(text: experiment.change, emphasis: .body, origin: .carried),
            ],
            action: ExperimentCopy.acknowledgeTitle
        )
        if settlement.verdict != .cannotTell {
            copy.caveat = experiment.caveat
        }

        return carrying(copy,
                        spoken: "\(eyebrow). \(result) \(ExperimentCopy.testedPrefix) "
                            + "\(experiment.change)"
                            + (settlement.verdict == .cannotTell
                               ? "" : " Bear in mind: \(experiment.caveat)"),
                        displacedActivityName: displacedActivityName,
                        displacedSessionId: displacedSessionId)
    }

    // MARK: Unfinished reflection

    private static let askAction = "Add how it felt"

    private static func askLine(activityName: String) -> String {
        "You logged \(activityName) but haven't said how it felt."
    }

    private static func reflectionCopy(activityName: String?, sessionId: UUID) -> SlotCopy {
        let line = askLine(activityName: activityName ?? "a session")
        return SlotCopy(
            eyebrow: "One thing left",
            lines: [SlotLine(text: line, emphasis: .lead, origin: .authored)],
            action: askAction,
            accessibilityLabel: line
        )
    }

    // MARK: Upgrade prompt

    /// Names how many recommendations this person's own record would produce, and
    /// nothing else.
    ///
    /// "In your own record" is load-bearing: BR-25 forbids any comparison against
    /// other people, and the surprise ranking's prior — which is what makes one of
    /// these worth reading before another — may not be reached for obliquely with
    /// "unusually" or "rare" either. "Held up" keeps the prompt in the same voice
    /// as the thing it is selling, so paying does not change what the sentence
    /// sounded like it promised.
    private static func promptCopy(count: Int) -> SlotCopy {
        let lead = count == 1
            ? "One pattern in your own record has held up."
            : "\(spelled(count).capitalizedFirst) patterns in your own record have held up."
        let support = count == 1
            ? "Membership is where it becomes a recommendation."
            : "Membership is where they become recommendations."

        return SlotCopy(
            eyebrow: "Pattern membership",
            lines: [
                SlotLine(text: lead, emphasis: .lead, origin: .authored),
                SlotLine(text: support, emphasis: .support, origin: .authored),
            ],
            accessibilityLabel: "\(lead) \(support)"
        )
    }

    // MARK: Lead observation

    private static func observationCopy(_ insight: Insight?) -> SlotCopy {
        guard let insight else { return SlotCopy() }
        return SlotCopy(
            eyebrow: "Here's something we're noticing",
            lines: [
                SlotLine(text: insight.statement, emphasis: .lead, origin: .carried),
                SlotLine(text: insight.evidence.summary, emphasis: .support, origin: .carried),
            ],
            accessibilityLabel: "\(insight.statement) \(insight.evidence.summary)"
        )
    }

    // MARK: Evidence progress

    /// A floor stated as a floor, in words as well as in the mark.
    ///
    /// BR-28, and the rule this whole surface exists to obey. The sentence names a
    /// necessary condition and never a sufficient one: twelve days is what has to
    /// be true *before* a comparison can be tested, not what produces one. There
    /// is no date, no "until", no "then", and no count of anything remaining,
    /// because every one of those turns the figure into a countdown — and a
    /// countdown that empties and delivers nothing is the one thing that member
    /// will remember the product for.
    ///
    /// The figure counts days rather than sessions because days are what the
    /// engine counts. Today's old warm-up line counted sessions against a constant
    /// of twelve, which was a product heuristic and never the engine's condition.
    private static func progressCopy(days: Int) -> SlotCopy {
        let figure = "\(days) of \(EvidenceFloor.days) days with a rating"
        let floor = "At least twelve days before anything can be tested."
        return SlotCopy(
            eyebrow: "Evidence so far",
            lines: [
                SlotLine(text: figure, emphasis: .lead, origin: .authored),
                SlotLine(text: floor, emphasis: .support, origin: .authored),
            ],
            // The mark is decorative on its own, so the figure has to be spoken.
            accessibilityLabel: "\(figure). \(floor)"
        )
    }

    // MARK: Still looking

    /// The engine met its floor and found nothing, and is entitled to say so
    /// forever.
    ///
    /// Two things this may not do. It may not imply something is being withheld —
    /// hence "an answer, not a missing one", which says outright that the empty
    /// result *is* the result. And it may not imply that more logging will change
    /// it, because for somebody whose days genuinely are flat it will not, and
    /// that is the engine being right rather than slow. So no "yet", which is a
    /// promise in one syllable, and no suggestion about what to log next.
    private static func stillLookingCopy() -> SlotCopy {
        let lead = "Nothing in your record stands apart from the rest."
        let support = "Evenly matched days are an answer, not a missing one."
        return SlotCopy(
            eyebrow: "Still looking",
            lines: [
                SlotLine(text: lead, emphasis: .lead, origin: .authored),
                SlotLine(text: support, emphasis: .support, origin: .authored),
            ],
            accessibilityLabel: "\(lead) \(support)"
        )
    }

    /// Counts are spelled in prose and set as numerals in a figure, which is the
    /// register the rest of the app reads in.
    private static func spelled(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six",
                     "seven", "eight", "nine", "ten", "eleven", "twelve"]
        return words.indices.contains(n) ? words[n] : "\(n)"
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

// MARK: - Gathering the state

extension HourssStore {

    /// What the recommendation layer would produce for this person, run without
    /// reference to whether they can see it.
    ///
    /// A.11 requires this: the prompt names the number of *recommendations*, so
    /// the layer has to run for members who are not entitled to its output.
    /// Naming surviving claims instead would be the same mis-selling one step
    /// removed, since a claim with nothing honest to suggest about it never
    /// becomes a recommendation.
    func slotRecommendations() -> [Recommendation] {
        let rows = ObservationBuilder.rows(
            sessions: sessions,
            reflections: reflections,
            activities: activities,
            healthByDay: healthByDay,
            residuals: physiologyReadings,
            workdays: profile.workdays
        )
        return Recommendations.build(
            for: EngineInput(observations: rows, priorities: profile.priorities)
        )
    }

    /// The slot's inputs, gathered in one place.
    ///
    /// Takes the recommendations rather than computing them, because the layer
    /// runs the whole engine and a view body is not a place to do that.
    func slotState(on day: Date,
                   recommendations: [Recommendation],
                   proposals: [ExperimentDesign.Proposal] = []) -> SlotState {
        let lead = proposals.first
        return SlotState(
            tier: membership.tier,
            ratedDayCount: ratedDayCount,
            unratedSessionId: unratedSessions(on: day).first?.id,
            recommendationCount: recommendations.count,
            leadRecommendationId: recommendations.first?.id,
            leadInsightId: visibleInsights.first?.id,
            settledExperimentId: unacknowledgedExperiment?.id,
            activeExperimentId: activeExperiment?.id,
            proposalId: lead?.id,
            proposalRequiresMembership: lead?.requiresMembership ?? false
        )
    }
}

// MARK: - The band

/// One thing, beneath the day's record.
///
/// The spec caps this at a single prompt — a feed of them would be the thing the
/// product is explicitly not — and the composition is identical either side of an
/// entitlement change, so nothing appears or disappears on purchase.
struct ObservationSlotView: View {
    @Environment(HourssStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let state: SlotState
    /// Passed in rather than computed: building these runs the whole engine, and
    /// a view body re-evaluates far more often than the engine should.
    let recommendations: [Recommendation]
    /// Proposals, for the same reason — `ExperimentDesign` runs the engine and the
    /// correction before it has anything to offer.
    var proposals: [ExperimentDesign.Proposal] = []
    /// How much of a running window has happened. Passed in because reading one
    /// resamples two thousand times, which a view body must never do.
    var activeReading: ExperimentOutcome.Reading?
    /// Whole days left of a running window. Computed by the caller, which is also
    /// the only place entitled to read the clock.
    var daysRemaining: Int = 0
    /// The day being drawn. Passed from the screen that already read the clock.
    var now: Date = Date()

    /// The proposal whose sheet is up, if one is.
    ///
    /// State rather than a parameter, so raising the sheet costs this view's
    /// initialiser nothing — three screens offer a proposal and each one owns its
    /// own presentation.
    @State private var sheetProposal: ExperimentDesign.Proposal?

    private var content: SlotContent { ObservationSlot.content(for: state) }

    private var copy: SlotCopy {
        let displacedId = ObservationSlot.displacedReflection(for: state)
        return ObservationSlot.copy(
            for: content,
            unratedActivityName: state.unratedSessionId.flatMap(activityName),
            insight: state.leadInsightId.flatMap { id in store.visibleInsights.first { $0.id == id } },
            recommendation: state.leadRecommendationId.flatMap { id in
                recommendations.first { $0.id == id }
            },
            proposal: state.proposalId.flatMap { id in proposals.first { $0.id == id } },
            experiment: experiment(for: content),
            reading: activeReading,
            daysRemaining: daysRemaining,
            now: now,
            displacedActivityName: displacedId.flatMap(activityName),
            displacedSessionId: displacedId
        )
    }

    /// The experiment a content refers to, where it refers to one.
    ///
    /// Resolved from the store by the id in the state rather than passed in, because
    /// an experiment is a stored value and reading one costs nothing — unlike the
    /// proposals and the reading above, which both run the engine.
    private func experiment(for content: SlotContent) -> Experiment? {
        switch content {
        case let .settledExperiment(id), let .activeExperiment(id):
            return store.experiments.first { $0.id == id }
        default:
            return nil
        }
    }

    var body: some View {
        if case .none = content {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Space.sm) {
                // The rule separates the band from the day above it. A card that
                // carries its own surface does not need one — the surface is already
                // the boundary, and a rule across the canvas directly above a filled
                // block reads as a seam rather than a division.
                if !isCarded { HRule() }

                VStack(alignment: .leading, spacing: Space.xs) {
                    Eyebrow(copy.eyebrow)
                    ForEach(Array(copy.lines.enumerated()), id: \.offset) { _, line in
                        text(for: line)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(copy.accessibilityLabel)

                if case let .evidenceProgress(days) = content { mark(days: days) }

                if let caveat = copy.caveat { caveatBlock(caveat) }

                experimentActions

                // The reflection link, for the states whose own action *is* the
                // rating. An experiment card has its own controls above and must not
                // also borrow this one, or a proposal would offer "Start this" and
                // "Add how it felt" as though they were the same kind of thing.
                if let action = copy.action, let sessionId = state.unratedSessionId,
                   !contentIsExperiment {
                    reflectionLink(title: action, sessionId: sessionId)
                }

                if let ask = copy.ask { askBlock(ask) }
            }
            .modifier(SlotSurface(carded: isCarded))
            .padding(.top, roomAbove)
            // Accepting, refusing, stopping or acknowledging replaces the whole band,
            // and the four of them are the only taps on Today that do. Keyed to the
            // content rather than to any one id so a hand-off between two experiment
            // states reads as one movement; Reduce Motion lands on the finished state.
            .animation(Motion.content(reduced: reduceMotion), value: content)
            // Agreeing is a decision, so it happens on a screen of its own. Nothing
            // is started by anything on this band.
            .sheet(item: $sheetProposal) { proposal in
                TestProposalSheet(proposal: proposal)
            }
        }
    }

    /// Space above the band, from how rare what it is showing is.
    ///
    /// **The same lever and the same two tokens `HealthFactRow` uses**, for the same
    /// reason: `DESIGN.md` records a second rule weight and a full-bleed canvas both
    /// reverted whole, and closes the first with the conclusion that the lever is
    /// space rather than more lines. A test's two ends — the offer and the result —
    /// are the rarest things this app shows; everything else here is routine by
    /// comparison.
    ///
    /// **Driven off `isCarded` rather than off the content, deliberately.** The room
    /// and the fill answer the same question and were two switches on the same fact
    /// until a proposal took the surface, at which point they could have disagreed:
    /// a filled block with `Space.md` above it reads as crowding the timeline rather
    /// than following it. One expression, so the two cannot drift.
    ///
    /// Nothing else varies — no colour, badge, border or type size — and the
    /// ordinary case keeps the padding it always had, so this adds space to the two
    /// cards rather than taking it from the others.
    private var roomAbove: CGFloat { isCarded ? Space.lg : Space.md }

    /// Whether this band is drawn as a filled card rather than as a ruled section.
    ///
    /// **Two states, and they are the two ends of one thing.** The owner asked for
    /// cards to differ by how important they are, and the system already answers
    /// that: the lead insight on Patterns is a forest block while everything beside
    /// it is a ruled row. This extends that one precedent rather than introducing a
    /// scale of colours — a palette where four things are emphasised differently is
    /// a palette where nothing is emphasised. Two of the slot's seven states are
    /// filled; the other five are ruled sections, unchanged.
    ///
    /// **This reverses the judgement the paragraph below records, and the paragraph
    /// stays because the reversal is the useful part.** It read:
    ///
    /// > So the settled result gets it and nothing else does. It is the rarest thing
    /// > the app can show, it appears once per experiment, and it is the only card
    /// > here a person waited a fortnight for. A proposal is a close second and
    /// > deliberately misses: it arrives whenever the engine has something, which
    /// > over a year is often, and a card that is emphatic every other week is just
    /// > the house style.
    ///
    /// That is right about frequency and wrong about importance, and frequency is
    /// the smaller consideration. Agreeing to a test is the most consequential thing
    /// this app asks anybody to do — it is the whole feature, and the result the
    /// settled card celebrates does not exist unless somebody said yes to this one
    /// first. Drawing the end of the lifecycle loudly and its beginning quietly was
    /// emphasising the part nobody has to decide anything about.
    ///
    /// The frequency objection is also smaller in practice than it reads. A proposal
    /// is suppressed for the whole of a running window, a declined hypothesis is
    /// never offered again, and a tested one is excluded — so the card is absent for
    /// a fortnight at a time and the "every other week" case is close to its upper
    /// bound rather than its average.
    ///
    /// **Colour is never the only carrier.** The eyebrow says "It held up", "It did
    /// not hold up", "Not enough to tell", "Worth testing", "Test what held up" or
    /// "A place to start" in words, so the surface reinforces a distinction that
    /// survives being read aloud or seen in greyscale.
    ///
    /// **Two filled cards cannot come from here.** `content` is one value, so the
    /// band draws one state and never two — see `ObservationSlot.isCarded(_:)`,
    /// which is where that is asserted. The one place on Today where a second forest
    /// block *can* appear beside this one is `ActiveSessionPanel`, which is not this
    /// file's to decide and was already true of the settled card.
    private var isCarded: Bool { ObservationSlot.isCarded(content) }

    /// The surface this band is drawn on, which decides its secondary copy colour.
    ///
    /// **Not read from the environment, and it cannot be.** `SlotSurface` sets
    /// `\.surface` on the band, so children rendered inside it see forest — but this
    /// view is the one *applying* that modifier, and it would read whatever its own
    /// parent set, which is canvas. Deriving it from the same flag that drives the
    /// fill is the only way the two cannot disagree.
    ///
    /// Going through `Surface.secondary` rather than naming a colour is the point:
    /// `Surface.swift` exists so that nothing hardcodes a pairing the design system
    /// did not sanction, and three places here were doing exactly that. On canvas
    /// `muted` was right and the bug was invisible; the moment a band was filled with
    /// forest, the same grey landed on dark green.
    private var surface: Surface { isCarded ? .forest : .canvas }

    private var contentIsExperiment: Bool {
        switch content {
        case .settledExperiment, .activeExperiment, .experimentProposal: true
        default: false
        }
    }

    /// The controls an experiment card carries.
    ///
    /// **A proposal has one control now, and it decides nothing.** Three used to sit
    /// here: accept, accept-with-drawn-days, and refuse — the first of them a text
    /// link weighing exactly as much as "Add how it felt", and one tap on it fixed a
    /// hypothesis, both arms and a fortnight. All three moved into
    /// `TestProposalSheet`, where the four questions somebody has before agreeing
    /// are answered first and the ask for a drawn window has room to be read rather
    /// than 11pt of mono under a link. What is left here is the way in.
    ///
    /// That also un-crowds the card: the band showed a change, a premise, sometimes
    /// a Health reading, a caveat, two accepts, a paragraph and a refusal, and the
    /// thing it was least able to do was make any one of them look important.
    ///
    /// **Stopping is plain and quiet.** It is the last control on an active card and
    /// says what it does. Abandoning is free and uncounted, so nothing here warns,
    /// confirms or asks whether they are sure — a confirmation would make stopping
    /// feel like a failure being recorded, which is exactly what it is not.
    @ViewBuilder
    private var experimentActions: some View {
        switch content {
        case .experimentProposal:
            if let proposal = state.proposalId.flatMap({ id in proposals.first { $0.id == id } }) {
                DirectionalLink(title: ExperimentCopy.openTitle, arrow: "→") {
                    sheetProposal = proposal
                }
                .accessibilityIdentifier("open-proposal")
            }

        case let .activeExperiment(id):
            if let experiment = store.experiments.first(where: { $0.id == id }) {
                DirectionalLink(title: ExperimentCopy.stopTitle, arrow: "→") {
                    store.abandonExperiment(experiment)
                }
                .accessibilityIdentifier("abandon-experiment")
            }

        case let .settledExperiment(id):
            if let experiment = store.experiments.first(where: { $0.id == id }) {
                DirectionalLink(title: ExperimentCopy.acknowledgeTitle, arrow: "→") {
                    store.acknowledgeExperiment(experiment)
                }
                .accessibilityIdentifier("acknowledge-experiment")
            }

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func text(for line: SlotLine) -> some View {
        switch line.emphasis {
        case .lead:
            Text(line.text)
                .textStyle(.sectionLead)
                .fixedSize(horizontal: false, vertical: true)
        case .body:
            Text(line.text)
                .textStyle(.body)
                .foregroundStyle(surface.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .support:
            Text(line.text)
                .textStyle(.label)
                .foregroundStyle(surface.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Twelve segments, one per day. A day either happened or it did not, so a
    /// filled fraction of a continuous bar would be the wrong shape — it implies a
    /// smooth approach to a threshold that is actually reached one whole day at a
    /// time. Hidden from VoiceOver because the figure above already speaks.
    private func mark(days: Int) -> some View {
        CoverageMark(segments: (0..<EvidenceFloor.days).map { $0 < days })
            .accessibilityHidden(true)
    }

    private func caveatBlock(_ caveat: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Eyebrow("Bear in mind")
            Text(caveat)
                .textStyle(.label)
                .foregroundStyle(surface.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bear in mind: \(caveat)")
    }

    /// The ask, stacked under a recommendation rather than displaced by it. Same
    /// action and same identifier as when it owns the slot, so the route to a
    /// rating does not change shape depending on what else is on screen.
    private func askBlock(_ ask: SlotAsk) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HRule()
            Text(ask.line)
                .textStyle(.body)
                .fixedSize(horizontal: false, vertical: true)
            reflectionLink(title: ask.action, sessionId: ask.sessionId)
        }
        .padding(.top, Space.xs)
    }

    private func reflectionLink(title: String, sessionId: UUID) -> some View {
        DirectionalLink(title: title, arrow: "→") {
            store.pendingReflectionSessionId = sessionId
        }
        .accessibilityIdentifier("add-missing-reflection")
    }

    private func activityName(_ sessionId: UUID) -> String? {
        store.sessions.first { $0.id == sessionId }.map { store.activityName($0.activityId) }
    }
}
