import Foundation
import Testing
@testable import Hourss

/// That a card names its own standing, and that a lead's premise stays true as its
/// evidence piles up.
@Suite("Experiment standing copy")
struct ExperimentStandingCopyTests {

    private func finding(days: Int, focusLabel: String = "Morning") -> Finding {
        Finding(
            hypothesis: Hypothesis(
                id: "time.morning.vs.rest.feeling", type: .bestTimeWindow, outcome: .feeling,
                focusLabel: focusLabel, baselineLabel: "The rest of your day",
                focus: { _ in true }, baseline: { _ in false },
                phrase: { _ in "Your morning sessions have felt more energizing." },
                caveat: "Time of day travels with whatever you tend to schedule then."
            ),
            comparison: Statistics.Comparison(
                delta: 0.2, low: -0.1, high: 0.5,
                focusCount: days, baselineCount: days,
                focusDays: days, baselineDays: days, pValue: 0.2
            ),
            focusSessionIds: [], baselineSessionIds: [],
            focusCoverage: 0.8, baselineCoverage: 0.8,
            survivesCorrection: false, windowDays: 42
        )
    }

    private func premise(days: Int) -> String {
        ExperimentCopy.premise(for: finding(days: days), standing: .lead, days: days)
    }

    // MARK: The lead premise

    @Test("A thin lead says so far, because little has been seen")
    func thinLeadSaysSoFar() {
        #expect(premise(days: 6).contains("so far"))
        #expect(premise(days: 6).contains("6 days"))
        #expect(premise(days: 13).contains("so far"))
    }

    /// The case that made this worth splitting.
    @Test("A lead with a fortnight behind it does not say so far")
    func heavyLeadDoesNotSaySoFar() {
        // "So far" says the app has not looked much. At sixteen days it has looked a
        // great deal and found nothing that separates — the opposite statement about
        // the same number.
        let line = premise(days: 16)
        #expect(!line.contains("so far"))
        #expect(line.contains("16 days"))
        #expect(line.contains("not clearly enough to call it"))
    }

    @Test("The split is the experiment window, and both sides of it hold")
    func theBoundary() {
        let window = Experiment.defaultWindowDays
        #expect(premise(days: window - 1).contains("so far"))
        #expect(!premise(days: window).contains("so far"))
    }

    @Test("Both forms stay singular at one day")
    func singular() {
        #expect(premise(days: 1).contains("1 day."))
        #expect(!premise(days: 1).contains("1 days"))
    }

    @Test("Neither form claims the pattern will hold")
    func noPromise() {
        for days in [6, 13, 14, 16, 40] {
            let line = premise(days: days).lowercased()
            for word in ["yet", "soon", "will", "proves", "shows that", "because"] {
                #expect(!line.contains(word),
                        Comment(rawValue: "a lead premise at \(days) days said '\(word)': \(line)"))
            }
        }
    }

    // MARK: The eyebrow

    @Test("Each standing names itself differently")
    func threeStandingsThreeWords() {
        let words = ExperimentDesign.Standing.allCases.map(ExperimentCopy.eyebrow(for:))
        // A starter borrowing the lead's word was the one place a card said more
        // than it knew: both read "Worth testing" though only one has evidence.
        #expect(Set(words).count == words.count, "two standings share an eyebrow")
        #expect(ExperimentCopy.eyebrow(for: .starter) != ExperimentCopy.eyebrow(for: .lead))
    }

    @Test("A starter's eyebrow names no evidence")
    func starterClaimsNothing() {
        let word = ExperimentCopy.eyebrow(for: .starter).lowercased()
        for claim in ["held", "worth", "pattern", "found", "strong", "your"] {
            #expect(!word.contains(claim),
                    Comment(rawValue: "a starter's eyebrow implied '\(claim)': \(word)"))
        }
    }

    @Test("Every eyebrow is allowed on screen")
    func eyebrowsPassTheGuard() {
        for standing in ExperimentDesign.Standing.allCases {
            let text = ExperimentCopy.eyebrow(for: standing)
            let offence = NarrationGuard.offence(in: text,
                                                 allowingFigures: NarrationGuard.figures(in: text))
            switch offence {
            case .none, .instruction: continue
            case .some(let found):
                Issue.record("\"\(text)\" broke a rule that still applies: \(found)")
            }
        }
    }
}

/// That the app uses one word for a session, everywhere somebody is asked to act.
@Suite("Change vocabulary")
struct ChangeVocabularyTests {

    /// Every change sentence the app can produce, across both window kinds.
    ///
    /// Driven off `experimentableTypes` so a type admitted later is swept without
    /// anybody remembering to add it here.
    private var everyChange: [String] {
        var out: [String] = []
        for type in ExperimentDesign.experimentableTypes.sorted(by: { $0.rawValue < $1.rawValue }) {
            for metric in [HealthMetric.sleepHours, .steps, nil] {
                for outcome in [Outcome.feeling, .heartRateResidual] {
                    if let c = ExperimentCopy.change(type: type, focusLabel: "Morning",
                                                     metric: metric, outcome: outcome) {
                        out.append(c)
                    }
                }
            }
            if let c = ExperimentCopy.randomisedChange(type: type, focusLabel: "Morning") {
                out.append(c)
            }
        }
        return out
    }

    @Test("No change sentence says block")
    func noJargon() {
        // "Block" appeared nowhere else in the app. Every other surface says
        // sessions, so a reader met the word for the first time in the one sentence
        // they were being asked to act on.
        #expect(!everyChange.isEmpty, "no change sentences were produced")
        for line in everyChange {
            #expect(!line.lowercased().contains("block"),
                    Comment(rawValue: "a change said 'block': \(line)"))
        }
    }

    @Test("Every change names a session and a length of time")
    func saysWhatAndHowLong() {
        for line in everyChange {
            #expect(line.lowercased().contains("session"),
                    Comment(rawValue: "a change named no session: \(line)"))
        }
    }
}
