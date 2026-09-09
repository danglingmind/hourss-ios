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

    var meetsEvidenceFloor: Bool { ratedDayCount >= EvidenceFloor.days }
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
    static func displacedReflection(for state: SlotState) -> UUID? {
        guard case .recommendation = content(for: state) else { return nil }
        return state.unratedSessionId
    }
}

// MARK: - The words

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
        displacedActivityName: String? = nil,
        displacedSessionId: UUID? = nil
    ) -> SlotCopy {
        switch content {
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
    func slotState(on day: Date, recommendations: [Recommendation]) -> SlotState {
        SlotState(
            tier: membership.tier,
            ratedDayCount: ratedDayCount,
            unratedSessionId: unratedSessions(on: day).first?.id,
            recommendationCount: recommendations.count,
            leadRecommendationId: recommendations.first?.id,
            leadInsightId: visibleInsights.first?.id
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

    let state: SlotState
    /// Passed in rather than computed: building these runs the whole engine, and
    /// a view body re-evaluates far more often than the engine should.
    let recommendations: [Recommendation]

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
            displacedActivityName: displacedId.flatMap(activityName),
            displacedSessionId: displacedId
        )
    }

    var body: some View {
        if case .none = content {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Space.sm) {
                HRule()

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

                if let action = copy.action, let sessionId = state.unratedSessionId {
                    reflectionLink(title: action, sessionId: sessionId)
                }

                if let ask = copy.ask { askBlock(ask) }
            }
            .padding(.top, Space.md)
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
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        case .support:
            Text(line.text)
                .textStyle(.label)
                .foregroundStyle(Color.muted)
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
                .foregroundStyle(Color.muted)
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
