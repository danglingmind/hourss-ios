import Testing
import Foundation
@testable import Hourss

/// Today's observation slot: which of the five contents owns it, and what it is
/// allowed to say once it does.
///
/// Everything here tests values rather than pixels. That is the whole reason
/// `SlotContent` is an enum and `SlotCopy` is a struct — the precedence in PRD
/// A.11 and the copy bounds in BR-28 and BR-29 are business rules, and a business
/// rule buried in a `body` can only be checked by looking at a screen.
@Suite("Today's observation slot")
@MainActor
struct SlotTests {

    // MARK: - Fixtures

    /// A state in which every row of the precedence table applies at once, so any
    /// single row can be tested by removing the ones above it rather than by
    /// building a fresh situation each time and hoping it isolates what it claims.
    private func everythingAtOnce(tier: Tier = .member) -> SlotState {
        SlotState(
            tier: tier,
            ratedDayCount: 40,
            unratedSessionId: UUID(),
            recommendationCount: 3,
            leadRecommendationId: UUID(),
            leadInsightId: UUID()
        )
    }

    private func store(for person: SyntheticCohort.Person,
                       priorities: [Priority] = [.focus, .balance, .energy]) -> HourssStore {
        let store = HourssStore(seeded: false)
        store.profile.priorities = priorities
        store.activities = person.activities
        store.sessions = person.sessions
        store.reflections = person.reflections
        store.applyHealthContext(person.healthByDay)
        return store
    }

    // MARK: - Precedence

    @Test("Each row of the table wins over every row below it")
    func precedenceIsOrdered() {
        var state = everythingAtOnce()

        // 1 — a recommendation, over the ask, the prompt, the observation and the mark.
        let recommendationId = state.leadRecommendationId
        #expect(ObservationSlot.content(for: state) == .recommendation(id: recommendationId!))

        // 2 — the ask, once there is no recommendation to show.
        state.leadRecommendationId = nil
        let sessionId = state.unratedSessionId
        #expect(ObservationSlot.content(for: state) == .unfinishedReflection(sessionId: sessionId!))

        // 3 — the prompt. Only reachable unentitled, which is the point of it.
        state.tier = .free
        state.unratedSessionId = nil
        #expect(ObservationSlot.content(for: state) == .upgradePrompt(count: 3))

        // 4 — the lead observation.
        state.recommendationCount = 0
        let insightId = state.leadInsightId
        #expect(ObservationSlot.content(for: state) == .leadObservation(id: insightId!))

        // 5 — and finally the mark, in its floor-met form.
        state.leadInsightId = nil
        #expect(ObservationSlot.content(for: state) == .stillLooking)
    }

    @Test("An unfinished reflection outranks the upgrade prompt")
    func askOutranksPrompt() {
        // Asking somebody to pay before asking for the rating the engine runs on
        // has the product's own dependency backwards.
        let sessionId = UUID()
        let state = SlotState(
            tier: .free,
            ratedDayCount: 30,
            unratedSessionId: sessionId,
            recommendationCount: 2
        )
        #expect(ObservationSlot.content(for: state) == .unfinishedReflection(sessionId: sessionId))
    }

    @Test("The slot always has content")
    func neverEmpty() {
        // Every combination of the values that drive it, which is small enough to
        // enumerate outright.
        for tier in Tier.allCases {
            for days in [0, 1, 11, 12, 40] {
                for unrated in [nil, UUID()] {
                    for count in [0, 1, 4] {
                        for lead in [nil, UUID()] {
                            for insight in [nil, UUID()] {
                                let state = SlotState(
                                    tier: tier, ratedDayCount: days, unratedSessionId: unrated,
                                    recommendationCount: count, leadRecommendationId: lead,
                                    leadInsightId: insight
                                )
                                #expect(ObservationSlot.content(for: state) != .none)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - No pitch below the floor

    @Test("A free member with nothing surviving sees no membership wording at all")
    func nothingSurvivingMeansNoPitch() {
        // `flatline` is pure noise by construction, so no claim survives and no
        // recommendation can be built from one.
        let store = store(for: SyntheticCohort.flatline)
        let recommendations = store.slotRecommendations()
        #expect(recommendations.isEmpty, "the fixture stopped being flat")

        // Forced rather than read: `Membership` is a singleton over user defaults,
        // and a test asserting what a *free* member sees should say so itself
        // rather than inherit whatever the last run left behind.
        var state = store.slotState(on: Date(), recommendations: recommendations)
        state.tier = .free
        let content = ObservationSlot.content(for: state)
        if case .upgradePrompt = content { Issue.record("a prompt rendered with nothing behind it") }

        let copy = ObservationSlot.copy(
            for: content,
            insight: store.visibleInsights.first
        )
        for line in copy.allStrings {
            #expect(!line.lowercased().contains("membership"), Comment(rawValue: "membership named in: \(line)"))
            #expect(!line.lowercased().contains("upgrade"), Comment(rawValue: "upgrade named in: \(line)"))
        }
    }

    @Test("A free member below the floor sees progress, not a pitch")
    func belowFloorMeansNoPitch() {
        // Comparisons split within a single day can clear the engine's six-a-side
        // minimum on as few as six distinct days, so a recommendation genuinely
        // can exist under twelve. BR-29 says the prompt still must not appear.
        let state = SlotState(tier: .free, ratedDayCount: 7, recommendationCount: 2)
        #expect(ObservationSlot.content(for: state) == .evidenceProgress(days: 7))
    }

    @Test("Below the floor, both tiers see the identical progress state")
    func floorIsTierBlind() {
        for days in 0..<EvidenceFloor.days {
            let free = SlotState(tier: .free, ratedDayCount: days)
            let paid = SlotState(tier: .member, ratedDayCount: days)
            #expect(ObservationSlot.content(for: free) == ObservationSlot.content(for: paid))
            #expect(ObservationSlot.copy(for: ObservationSlot.content(for: free))
                    == ObservationSlot.copy(for: ObservationSlot.content(for: paid)))
        }
    }

    // MARK: - The figure

    @Test("The day count drives the progress state")
    func dayCountDrivesProgress() {
        for days in 0..<EvidenceFloor.days {
            let state = SlotState(ratedDayCount: days)
            #expect(ObservationSlot.content(for: state) == .evidenceProgress(days: days))
        }
        #expect(ObservationSlot.content(for: SlotState(ratedDayCount: EvidenceFloor.days)) == .stillLooking)
    }

    @Test("The figure counts days, not sessions")
    func figureCountsDays() {
        // Six sessions on one Tuesday are one day of evidence about Tuesdays. The
        // line this replaced counted sessions against a constant of twelve, which
        // was a product heuristic and never the engine's condition.
        let store = HourssStore(seeded: false)
        let activity = store.activities[0]
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 9))!

        for index in 0..<6 {
            let start = day.addingTimeInterval(Double(index) * 3600)
            let session = Session(activityId: activity.id, startAt: start,
                                  endAt: start.addingTimeInterval(1800))
            store.sessions.append(session)
            store.saveReflection(sessionId: session.id, feeling: 4, performance: 3, note: nil)
        }

        #expect(store.ratedDayCount == 1, "six sessions on one day counted as more than one day")
        #expect(store.eligibleSessionCount == 6, "the fixture did not produce six sessions")

        let state = store.slotState(on: Date(), recommendations: [])
        #expect(ObservationSlot.content(for: state) == .evidenceProgress(days: 1))
    }

    @Test("An unrated session adds no evidence")
    func unratedDaysDoNotCount() {
        // Unrated stays unknown. A day the engine cannot use is not a day of
        // evidence, and a figure that counted it would overstate the record.
        let store = HourssStore(seeded: false)
        let activity = store.activities[0]
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 9))!
        let session = Session(activityId: activity.id, startAt: day,
                              endAt: day.addingTimeInterval(1800))
        store.sessions.append(session)

        #expect(store.ratedDayCount == 0)
    }

    // MARK: - Floor met, nothing surviving

    @Test("Floor met with nothing surviving falls through to the lead observation")
    func fallsThroughToObservation() {
        let insightId = UUID()
        let state = SlotState(tier: .member, ratedDayCount: 30, leadInsightId: insightId)
        #expect(ObservationSlot.content(for: state) == .leadObservation(id: insightId))
    }

    @Test("And to still looking when there is no observation either")
    func fallsThroughToStillLooking() {
        let state = SlotState(tier: .member, ratedDayCount: 30)
        #expect(ObservationSlot.content(for: state) == .stillLooking)
    }

    @Test("Eighteen flat days is a met floor and no claim, not a warm-up")
    func shortHistoryIsNotWarmingUp() {
        // `shortHistory` carries a real effect and too little of it. The slot's own
        // floor is met — eighteen days is above twelve — so it must not still be
        // showing a mark, and it must not be showing a claim either.
        let store = store(for: SyntheticCohort.shortHistory)
        #expect(store.ratedDayCount >= EvidenceFloor.days, Comment(rawValue:
                "fixture has \(store.ratedDayCount) rated days, below the floor"))

        let state = store.slotState(on: Date(), recommendations: store.slotRecommendations())
        if case .evidenceProgress = ObservationSlot.content(for: state) {
            Issue.record("a met floor still rendered the mark")
        }
    }

    // MARK: - The prompt's count

    @Test("The prompt names the number of recommendations, not of surviving claims")
    func promptCountIsReal() {
        let store = store(for: SyntheticCohort.afternoonSlump)
        let recommendations = store.slotRecommendations()
        try? #require(!recommendations.isEmpty)

        // The fixture leaves a quarter of its sessions unrated, so today may well
        // carry an ask. Cleared here rather than worked around: this test is about
        // the number the prompt names, and the ask outranking it is a separate
        // rule with a test of its own.
        var state = store.slotState(on: Date(), recommendations: recommendations)
        state.unratedSessionId = nil

        #expect(state.meetsEvidenceFloor)
        #expect(ObservationSlot.content(for: state) == .upgradePrompt(count: recommendations.count))

        // What the count must not be: the number of claims that survived. Every
        // recommendation rests on one, but claims with nothing honest to suggest
        // about them never become one, so the two figures come apart.
        let copy = ObservationSlot.copy(for: ObservationSlot.content(for: state))
        let named = ["zero", "One", "Two", "Three", "Four", "Five", "Six"][recommendations.count]
        #expect(copy.lines.first?.text.hasPrefix(named) == true, Comment(rawValue:
                "prompt named something other than \(recommendations.count): \(copy.lines)"))
    }

    @Test("Where the count is zero the prompt does not render")
    func zeroCountDoesNotPrompt() {
        let state = SlotState(tier: .free, ratedDayCount: 30, recommendationCount: 0)
        #expect(ObservationSlot.content(for: state) == .stillLooking)
    }

    // MARK: - The collision

    @Test("A recommendation carries the rating it displaced")
    func recommendationCarriesTheAsk() {
        // A.11 records this and leaves it to be reconciled here. A recommendation
        // outranks the ask and persists between recomputes, so without this the
        // only route on Today to rating an earlier session could stay closed for
        // days at a time.
        let sessionId = UUID()
        var state = everythingAtOnce()
        state.unratedSessionId = sessionId

        #expect(ObservationSlot.displacedReflection(for: state) == sessionId)

        let recommendation = try? #require(store(for: SyntheticCohort.afternoonSlump)
            .slotRecommendations().first)
        let copy = ObservationSlot.copy(
            for: ObservationSlot.content(for: state),
            recommendation: recommendation,
            displacedActivityName: "Deep work",
            displacedSessionId: sessionId
        )
        #expect(copy.ask?.sessionId == sessionId)
        #expect(copy.ask?.action == "Add how it felt")
    }

    @Test("Nothing else reports a displaced rating")
    func onlyRecommendationsDisplace() {
        var state = everythingAtOnce()
        state.leadRecommendationId = nil
        // The ask now owns the slot, so nothing was pushed out of it.
        #expect(ObservationSlot.displacedReflection(for: state) == nil)

        state.unratedSessionId = nil
        state.leadRecommendationId = UUID()
        #expect(ObservationSlot.displacedReflection(for: state) == nil)
    }

    // MARK: - Copy

    @Test("The progress line states a floor and never a date")
    func progressStatesAFloor() {
        let copy = ObservationSlot.copy(for: .evidenceProgress(days: 7))
        #expect(copy.lines.map(\.text).contains("7 of 12 days with a rating"))
        #expect(copy.lines.map(\.text).contains("At least twelve days before anything can be tested."))
        // The mark is decorative; the figure has to survive in the spoken label.
        #expect(copy.accessibilityLabel.contains("7 of 12 days"))
    }

    @Test("Still looking neither withholds nor promises")
    func stillLookingIsHonest() {
        let copy = ObservationSlot.copy(for: .stillLooking)
        let text = copy.allStrings.joined(separator: " ").lowercased()
        // "Yet" is a promise in one syllable, and for somebody whose days genuinely
        // are flat it is a promise the engine cannot keep.
        for word in ["yet", "soon", "keep logging", "more data", "unlock", "locked"] {
            #expect(!text.contains(word), Comment(rawValue: "still looking said '\(word)': \(text)"))
        }
    }

    /// The sweep. Runs over the strings this file wrote, in every state.
    ///
    /// Deliberately not over carried strings: the registry's caveat for a
    /// time-of-day claim reads "Time of day travels with whatever you tend to
    /// schedule then", and folding that in here would only teach somebody to
    /// weaken the sweep rather than to fix a sentence. A.11 scopes the forecast
    /// half of it to the slot's own copy for the same reason.
    @Test("No slot copy carries a date, a countdown, an instruction or a comparison")
    func copySweep() {
        let banned = ["until", "then", "days left", "days to go", "days until",
                      "try", "most people", "average", "others", "typical",
                      "you should", "make sure", "aim to", "be sure to",
                      "we recommend", "you need to", "remember to", "consider "]
        let months = ["january", "february", "march", "april", "may", "june", "july",
                      "august", "september", "october", "november", "december"]
        let weekdays = ["monday", "tuesday", "wednesday", "thursday",
                        "friday", "saturday", "sunday"]

        for copy in everyStatesCopy() {
            for string in copy.authoredStrings {
                let text = string.lowercased()
                for phrase in banned {
                    #expect(!contains(word: phrase, in: text),
                            Comment(rawValue: "'\(phrase)' in slot copy: \(string)"))
                }
                for name in months + weekdays {
                    #expect(!text.contains(name), Comment(rawValue: "a date in slot copy: \(string)"))
                }
                #expect(text.range(of: #"\d{1,2}[/-]\d{1,2}"#, options: .regularExpression) == nil,
                        Comment(rawValue: "a date in slot copy: \(string)"))
            }
        }
    }

    @Test("A recommendation does not read as an experiment")
    func recommendationIsNotAnExperiment() {
        // If a recommendation says 'try', it has become the free tier's experiment
        // and the two tiers say the same thing in the same words.
        let recommendations = store(for: SyntheticCohort.afternoonSlump).slotRecommendations()
        #expect(!recommendations.isEmpty, "the fixture stopped producing recommendations")
        for recommendation in recommendations {
            #expect(!recommendation.action.lowercased().hasPrefix("try"),
                    Comment(rawValue: "a recommendation opened with 'try': \(recommendation.action)"))
        }
    }

    @Test("Every state speaks")
    func everyStateHasALabel() {
        for copy in everyStatesCopy() {
            #expect(!copy.accessibilityLabel.isEmpty)
            #expect(!copy.eyebrow.isEmpty)
            #expect(!copy.lines.isEmpty)
        }
    }

    // MARK: - Helpers

    /// One copy per state, with real engine strings where a state carries them.
    private func everyStatesCopy() -> [SlotCopy] {
        let store = store(for: SyntheticCohort.afternoonSlump)
        let recommendation = store.slotRecommendations().first
        let insight = store.visibleInsights.first
        let sessionId = UUID()

        return [
            ObservationSlot.copy(for: .recommendation(id: UUID()),
                                 recommendation: recommendation,
                                 displacedActivityName: "Deep work",
                                 displacedSessionId: sessionId),
            ObservationSlot.copy(for: .unfinishedReflection(sessionId: sessionId),
                                 unratedActivityName: "Deep work"),
            ObservationSlot.copy(for: .upgradePrompt(count: 1)),
            ObservationSlot.copy(for: .upgradePrompt(count: 3)),
            ObservationSlot.copy(for: .leadObservation(id: UUID()), insight: insight),
            ObservationSlot.copy(for: .evidenceProgress(days: 0)),
            ObservationSlot.copy(for: .evidenceProgress(days: 11)),
            ObservationSlot.copy(for: .stillLooking),
        ]
    }

    /// Whole-word containment, so "entry" is not a "try" and "strengthen" is not a
    /// "then".
    private func contains(word: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        let pattern = word.hasSuffix(" ") ? "\\b\(escaped.trimmingCharacters(in: .whitespaces))\\b"
                                          : "\\b\(escaped)\\b"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
