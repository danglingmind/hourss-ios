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
