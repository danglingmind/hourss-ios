import Foundation
import Testing
@testable import Hourss

/// That a waiting question says what is missing in a sentence somebody can act on.
@Suite("Question copy")
struct QuestionCopyTests {

    private func pending(id: String, focusLabel: String, baselineLabel: String = "The rest",
                         focusDays: Int, baselineDays: Int) -> Engine.Pending {
        Engine.Pending(
            hypothesis: Hypothesis(
                id: id, type: .bestTimeWindow, outcome: .feeling,
                focusLabel: focusLabel, baselineLabel: baselineLabel,
                focus: { _ in true }, baseline: { _ in false },
                phrase: { _ in "" }, caveat: ""
            ),
            focusDays: focusDays, baselineDays: baselineDays
        )
    }

    /// The sentence that sent me looking: "Nothing logged in your 180 min or more yet."
    @Test("Every family gets a sentence that reads")
    func familiesReadCorrectly() {
        let cases: [(String, String, String)] = [
            ("time.morning.vs.rest.feeling", "Morning", "sessions in your morning"),
            ("duration.extended.vs.rest.feeling", "180 min or more", "sessions of 180 min or more"),
            ("activity.deep-work.vs.rest.feeling", "Deep work", "sessions of Deep work"),
            ("workday.non.vs.work.feeling", "Non-workdays", "sessions on non-workdays"),
        ]
        for (id, label, expected) in cases {
            let line = QuestionCopy.waiting(
                pending(id: id, focusLabel: label, focusDays: 0, baselineDays: 9))
            #expect(line == "No \(expected) yet.",
                    Comment(rawValue: "\(id) read: \(line)"))
            // Grammar, asserted rather than hoped for. "No a session" is what one
            // noun form for both sentences produces.
            #expect(!line.contains("No a "))
            // A duration written as a place reads as the app not paying attention.
            #expect(!line.contains("in your 180"))
        }
    }

    @Test("Short of a few days names the number and the thing")
    func shortfallIsActionable() {
        let line = QuestionCopy.waiting(
            pending(id: "activity.creative.vs.rest.feeling",
                    focusLabel: "Creative", focusDays: 3, baselineDays: 20))
        #expect(line == "3 more days with a session of Creative.")

        // Singular at one.
        let one = QuestionCopy.waiting(
            pending(id: "activity.creative.vs.rest.feeling",
                    focusLabel: "Creative", focusDays: 5, baselineDays: 20))
        #expect(one == "1 more day with a session of Creative.")
    }

    @Test("A thin other side asks for something different, not more of the same")
    func baselineShortfall() {
        // Everything is mornings. Telling somebody to log more mornings would be
        // telling them to do more of what has already filled one side.
        let line = QuestionCopy.waiting(
            pending(id: "time.morning.vs.rest.feeling", focusLabel: "Morning",
                    baselineLabel: "Rest of the day", focusDays: 20, baselineDays: 2))
        #expect(line.contains("4 more days"))
        #expect(line.contains("something other than"))
        #expect(line.contains("rest of the day"))
    }

    @Test("One side with nothing at all says so rather than quoting a number")
    func untouchedSaysSo() {
        let line = QuestionCopy.waiting(
            pending(id: "time.evening.vs.rest.feeling", focusLabel: "Evening",
                    focusDays: 0, baselineDays: 30))
        #expect(line == "No sessions in your evening yet.")
        #expect(!line.contains("6 more"))
    }

    @Test("Nothing promises a finding, anywhere")
    func nothingPromises() {
        // A question that opens may say nothing stood out. Copy implying otherwise
        // makes the screen a slot machine that mostly pays nothing.
        var lines = [QuestionCopy.noSeparation, QuestionCopy.waitingHeading]
        for days in [0, 2, 5] {
            lines.append(QuestionCopy.waiting(
                pending(id: "time.morning.vs.rest.feeling", focusLabel: "Morning",
                        focusDays: days, baselineDays: 20)))
        }
        for line in lines {
            let text = line.lowercased()
            for promise in ["unlock", "reveal", "discover", "find out", "will show",
                            "waiting to", "coming", "soon"] {
                #expect(!text.contains(promise),
                        Comment(rawValue: "'\(promise)' promised a finding: \(line)"))
            }
        }
        // And the measured non-answer does not say "yet", which is a promise in one
        // syllable for somebody whose days are genuinely flat.
        #expect(!QuestionCopy.noSeparation.lowercased().contains("yet"))
    }
}

/// That Patterns tells "not enough yet" apart from "measured, nothing separated".
@Suite("Patterns empty states")
@MainActor
struct PatternsEmptyStateTests {

    private static let start = Date(timeIntervalSince1970: 1_767_225_600)
    private static let calendar = Calendar.current

    private func store(_ entries: [(dayOffset: Int, hour: Int, feeling: Int)]) -> HourssStore {
        let store = HourssStore(repository: InMemoryRecordRepository())
        store.profile.priorities = [.focus, .energy]
        let activity = store.activities.first!
        var sessions: [Session] = []
        var reflections: [UUID: Reflection] = [:]
        for entry in entries {
            let day = Self.calendar.date(byAdding: .day, value: entry.dayOffset, to: Self.start)!
            let startAt = Self.calendar.date(bySettingHour: entry.hour, minute: 0, second: 0, of: day)!
            let session = Session(activityId: activity.id, startAt: startAt,
                                  endAt: startAt.addingTimeInterval(3600))
            sessions.append(session)
            reflections[session.id] = Reflection(sessionId: session.id, feelingScore: entry.feeling,
                                                 performanceScore: nil, note: nil, submittedAt: startAt)
        }
        store.sessions = sessions
        store.reflections = reflections
        store.rebuildInsights()
        return store
    }

    private func asked(_ store: HourssStore) -> Bool {
        let pending = Engine.pending(for: EngineInput(observations: store.engineObservations,
                                                      priorities: store.profile.priorities))
        return HypothesisRegistry.hypotheses(for: store.engineObservations).count > pending.count
    }

    @Test("A thin record has asked nothing, so it is still gathering")
    func thinRecordIsGathering() {
        // Three mornings. No split has six days a side, so nothing was compared.
        let store = store((0..<3).map { ($0, 9, 4) })
        #expect(store.isWarmingUp)
        #expect(!asked(store))
    }

    /// The state the owner was looking at: every bar full, no pattern, and a screen
    /// that said it was still gathering.
    @Test("A full record where nothing separates has asked plenty")
    func flatRecordHasBeenMeasured() {
        // Twelve days, mornings and afternoons on each, every rating identical. Six
        // a side on the timing split, so it is compared — and a constant rating
        // cannot separate, so nothing survives.
        var entries: [(Int, Int, Int)] = []
        for day in 0..<12 {
            entries.append((day, 9, 4))
            entries.append((day, 15, 4))
        }
        let store = store(entries)

        #expect(store.bestBalancedDays >= EvidenceFloor.perSide)
        #expect(asked(store), "the timing split should have been compared")
        // Nothing separated, so there is still no visible insight — and the screen
        // must say that rather than showing a progress bar sitting at full.
        #expect(store.isWarmingUp)
    }

    @Test("The two states cannot both be true of one record")
    func theyAreExclusive() {
        let thin = store((0..<3).map { ($0, 9, 4) })
        var entries: [(Int, Int, Int)] = []
        for day in 0..<12 { entries.append((day, 9, 4)); entries.append((day, 15, 4)) }
        let flat = store(entries)
        // One is gathering, the other has been measured. The screen branches on
        // exactly this, so they must never agree.
        #expect(asked(thin) != asked(flat))
    }

    // MARK: - Every priority has something in it

    /// The four things a priority section can hold, in the order it draws them.
    ///
    /// Mirrors the condition in `prioritySection` that prints "Nothing here has
    /// repeated enough to show." — deliberately a copy rather than shared, because
    /// the view's version is a `ViewBuilder` branch and the thing worth pinning is
    /// the arithmetic, not the layout. If the two drift, the section grows a state
    /// this suite does not know about, which is a failure worth having.
    private func holdings(
        _ store: HourssStore, _ priority: Priority, resamples: Int = 200
    ) -> (insights: Int, leads: Int, offers: Int, waiting: Int) {
        let input = EngineInput(observations: store.engineObservations,
                                priorities: store.profile.priorities)
        let waiting = Engine.pending(for: input)
        return (
            insights: store.visibleInsights.filter { priority.insightTypes.contains($0.type) }.count,
            leads: PatternsView.leads(in: store)
                .filter { priority.insightTypes.contains($0.publishedType) }.count,
            offers: store.experimentProposals(resamples: resamples)
                .filter { $0.priority == priority }.count,
            waiting: waiting.filter { priority.insightTypes.contains($0.hypothesis.type) }.count
        )
    }

    /// The bug the owner found: a thin record showed one sentence and no sections,
    /// so the person with the least to look at was the one person given nothing to
    /// do about it. Everything asserted here was already true of the engine — the
    /// screen simply could not reach it, because the warm-up state replaced the
    /// whole page instead of sitting above it.
    @Test("A warming-up priority still holds something to do or something to wait for")
    func warmUpPrioritiesAreNotEmpty() {
        let store = store((0..<3).map { ($0, 9, 4) })
        #expect(store.isWarmingUp, "three mornings should separate nothing")

        for priority in store.profile.priorities {
            let held = holdings(store, priority)
            #expect(held.offers + held.waiting > 0,
                    Comment(rawValue: "\(priority.title) had nothing: \(held)"))
        }
    }

    /// And the other warm-up state, for the same reason. A record that was measured
    /// and came out alike is not a record with nothing in its sections: every
    /// question that was asked is a lead row, and the offer stands either way.
    @Test("A measured-but-flat priority still holds something")
    func flatPrioritiesAreNotEmpty() {
        var entries: [(Int, Int, Int)] = []
        for day in 0..<12 { entries.append((day, 9, 4)); entries.append((day, 15, 4)) }
        let store = store(entries)
        #expect(store.isWarmingUp)
        #expect(asked(store))

        for priority in store.profile.priorities {
            let held = holdings(store, priority)
            let total = held.insights + held.leads + held.offers + held.waiting
            #expect(total > 0, Comment(rawValue: "\(priority.title) had nothing: \(held)"))
        }
    }
}
