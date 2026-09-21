import Testing
import Foundation
@testable import Hourss

/// The one-day comparison behind the post-rating card.
///
/// Most of what is tested here is refusal. The card says something about one
/// day, which is the weakest kind of statement this app makes, so the interesting
/// question is never "did it find the deviation" — it is "did it decline on the
/// days where the arithmetic would have been misleading".
@Suite("Day deviation")
@MainActor
struct DayDeviationTests {

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }

    private func day(_ back: Int) -> Date {
        calendar.date(byAdding: .day, value: -back, to: today)!
    }

    /// `count` prior days, every one of them recorded, newest at offset 1.
    private func series(_ count: Int, _ value: (Int) -> Double) -> [Date: Double] {
        var out: [Date: Double] = [:]
        for back in 1...count { out[day(back)] = value(back) }
        return out
    }

    // MARK: - What may be compared at all

    @Test("Only the four settled metrics are eligible")
    func allowlistIsExactlyTheSettledFour() {
        #expect(DayDeviation.eligibleMetrics == [.sleepHours, .hrv, .restingHeartRate, .respiratoryRate])
    }

    /// The failure this allowlist exists to prevent, stated as a test.
    ///
    /// `HealthService` reads with `end: Date()`, so today's row for a cumulative
    /// metric is however much of the day has happened. Feed the comparison the
    /// most extreme partial day imaginable — a thousand steps against a median of
    /// nine thousand, which is simply what lunchtime looks like — and it must have
    /// nothing to say.
    @Test("A partial cumulative day cannot produce a standout")
    func partialDayCannotFire() {
        var stepsByDay = series(60) { _ in 9_000 }
        stepsByDay[today] = 1_000

        var energyByDay = series(60) { _ in 600 }
        energyByDay[today] = 40

        var daylightByDay = series(60) { _ in 90 }
        daylightByDay[today] = 4

        let result = DayDeviation.standout(on: today, history: [
            .steps: stepsByDay,
            .activeEnergy: energyByDay,
            .daylightMinutes: daylightByDay,
        ])
        #expect(result == nil, "a mid-afternoon partial day was scored as a deviation")
    }

    @Test("A mean heart rate is never a standout")
    func heartRateIsNotADailyValue() {
        var byDay = series(60) { _ in 70.0 }
        byDay[today] = 110
        #expect(DayDeviation.standout(on: today, history: [.heartRate: byDay]) == nil)
    }

    // MARK: - The arithmetic

    /// Twenty prior nights, ten at 6.5h and ten at 7.5h: median 7.0, MAD 0.5, so
    /// the robust sigma is 0.5 × 1.4826 = 0.7413 and a 8.5h night sits 2.02 above.
    @Test("Robust z against a hand-computed series")
    func robustZIsCorrect() throws {
        var byDay = series(20) { back in back <= 10 ? 6.5 : 7.5 }
        byDay[today] = 8.5

        let result = DayDeviation.standout(on: today, history: [.sleepHours: byDay])
        let standout = try #require(result)
        #expect(standout.metric == .sleepHours)
        #expect(standout.value == 8.5)
        #expect(abs(standout.z - 1.5 / (0.5 * 1.4826)) < 0.0001)
        #expect(standout.historyDays == 20)
        #expect(standout.daysSinceMoreExtreme == nil, "nothing in the window was longer")
        #expect(standout.spanDays == 20)
        #expect(standout.isHigh)
    }

    @Test("A low day scores negative and reads as the low side")
    func lowSideIsSigned() throws {
        var byDay = series(20) { back in back <= 10 ? 6.5 : 7.5 }
        byDay[today] = 5.5

        let standout = try #require(DayDeviation.standout(on: today, history: [.sleepHours: byDay]))
        #expect(standout.z < 0)
        #expect(!standout.isHigh)
    }

    /// A metric that does not move must not manufacture an infinite score. Twenty
    /// identical nights give a MAD of exactly zero, and without the clamp the
    /// division is by nothing at all.
    @Test("Zero spread is clamped rather than divided by")
    func zeroMADIsClamped() throws {
        var byDay = series(20) { _ in 7.0 }
        byDay[today] = 7.5

        let standout = try #require(DayDeviation.standout(on: today, history: [.sleepHours: byDay]))
        #expect(standout.z.isFinite)
        // Half an hour against the fifteen-minute floor.
        #expect(abs(standout.z - 2.0) < 0.0001)
    }

    @Test("A half-minute difference on a rigid metric is not a record")
    func clampAlsoRefusesTrivia() {
        var byDay = series(30) { _ in 7.0 }
        byDay[today] = 7.2   // twelve minutes — inside the floor, so under 1.5σ

        #expect(DayDeviation.standout(on: today, history: [.sleepHours: byDay]) == nil)
    }

    /// Each metric's floor is in its own unit, so the clamp has to be read per
    /// metric or three of the four are wrong by an order of magnitude.
    @Test("Every eligible metric has a floor in its own unit")
    func floorsAreScaledPerMetric() {
        #expect(DayDeviation.spreadFloor(for: .sleepHours) == 0.25)
        #expect(DayDeviation.spreadFloor(for: .hrv) == 3)
        #expect(DayDeviation.spreadFloor(for: .restingHeartRate) == 1.5)
        #expect(DayDeviation.spreadFloor(for: .respiratoryRate) == 0.3)
    }

    // MARK: - Absence

    /// A day nobody recorded is absent, not zero. The same twenty readings spread
    /// over forty calendar days must give the same answer as twenty consecutive
    /// ones — if the gaps arrived as 0.0 the median would collapse and an ordinary
    /// night would score as a record.
    @Test("Missing days are excluded, never zeroed")
    func gapsAreNotZeroes() throws {
        var dense: [Date: Double] = [:]
        for back in 1...20 { dense[day(back)] = back <= 10 ? 6.5 : 7.5 }
        dense[today] = 8.5

        var sparse: [Date: Double] = [:]
        for index in 1...20 { sparse[day(index * 2)] = index <= 10 ? 6.5 : 7.5 }
        sparse[today] = 8.5

        let denseResult = try #require(DayDeviation.standout(on: today, history: [.sleepHours: dense]))
        let sparseResult = try #require(DayDeviation.standout(on: today, history: [.sleepHours: sparse]))

        #expect(abs(denseResult.z - sparseResult.z) < 0.0001)
        #expect(sparseResult.historyDays == 20, "the comparison counted days it never had")
    }

    // MARK: - The gates

    @Test("Thirteen days of history is not enough to say anything")
    func minimumHistoryGate() {
        var thin = series(13) { _ in 7.0 }
        thin[today] = 10.0
        #expect(DayDeviation.standout(on: today, history: [.sleepHours: thin]) == nil)

        var enough = series(14) { _ in 7.0 }
        enough[today] = 10.0
        #expect(DayDeviation.standout(on: today, history: [.sleepHours: enough]) != nil)
    }

    @Test("A deviation inside the noise says nothing")
    func minimumZGate() {
        var byDay = series(30) { back in back.isMultiple(of: 2) ? 6.5 : 7.5 }
        byDay[today] = 7.6
        #expect(DayDeviation.standout(on: today, history: [.sleepHours: byDay]) == nil)
    }

    /// "Your longest night in three days" is true and worthless.
    @Test("A superlative that only reaches back three days is not shown")
    func minimumSpanGate() {
        var byDay = series(30) { back in back == 3 ? 9.5 : (back.isMultiple(of: 2) ? 6.5 : 7.5) }
        byDay[today] = 8.6

        #expect(DayDeviation.standout(on: today, history: [.sleepHours: byDay]) == nil)
    }

    @Test("The span reaches back to the last day that beat it")
    func spanCountsBackToTheLastMoreExtremeDay() throws {
        var byDay = series(40) { back in back == 11 ? 9.5 : (back.isMultiple(of: 2) ? 6.5 : 7.5) }
        byDay[today] = 8.6

        let standout = try #require(DayDeviation.standout(on: today, history: [.sleepHours: byDay]))
        #expect(standout.daysSinceMoreExtreme == 11)
        #expect(standout.spanDays == 11)
    }

    /// A day that merely equalled today ends the run. Today is then joint longest,
    /// and "your longest night in forty days" would be one word of overclaim.
    @Test("An equal day ends the run")
    func equalDayEndsTheRun() {
        var byDay = series(40) { back in back == 5 ? 8.6 : (back.isMultiple(of: 2) ? 6.5 : 7.5) }
        byDay[today] = 8.6

        #expect(DayDeviation.standout(on: today, history: [.sleepHours: byDay]) == nil,
                "a tie five days ago should have cut the span below the floor")
    }

    @Test("A day with no reading for the metric is not compared")
    func todayMustHaveAValue() {
        let byDay = series(40) { _ in 7.0 }   // no entry for today
        #expect(DayDeviation.standout(on: today, history: [.sleepHours: byDay]) == nil)
    }

    // MARK: - Ranking

    @Test("The furthest-out metric wins")
    func rankingPicksTheLargestMagnitude() throws {
        var sleep = series(30) { back in back.isMultiple(of: 2) ? 6.5 : 7.5 }
        sleep[today] = 8.4                                   // ~1.9σ

        var hrv = series(30) { back in back.isMultiple(of: 2) ? 45.0 : 55.0 }
        hrv[today] = 95                                      // ~6.7σ

        let standout = try #require(DayDeviation.standout(on: today, history: [
            .sleepHours: sleep, .hrv: hrv,
        ]))
        #expect(standout.metric == .hrv)
    }

    /// Dictionaries have no order, and a card that differs between two launches on
    /// identical data is a bug nobody can reproduce.
    @Test("Ranking is deterministic, including on a tie")
    func rankingIsStable() {
        // Two metrics built to land on exactly the same |z|: both sit two clamped
        // floors above a rigid median.
        var sleep = series(30) { _ in 7.0 }
        sleep[today] = 7.0 + 2 * DayDeviation.spreadFloor(for: .sleepHours)

        var resting = series(30) { _ in 58.0 }
        resting[today] = 58.0 + 2 * DayDeviation.spreadFloor(for: .restingHeartRate)

        let history: [HealthMetric: [Date: Double]] = [.restingHeartRate: resting, .sleepHours: sleep]
        let first = DayDeviation.standout(on: today, history: history)
        let second = DayDeviation.standout(on: today, history: history)

        #expect(first == second)
        #expect(first?.metric == .sleepHours, "a tie should fall to the first metric in the allowlist")
    }
}

/// Every word the card can put on screen, swept against the list of things this
/// app does not say.
///
/// The card is the only place in the product where a health number is shown
/// immediately after a rating, which is exactly the position from which a
/// sentence most easily implies a cause. The sweep is cheap insurance against a
/// future edit that reads perfectly well and claims something the data cannot
/// support.
@Suite("Day context card copy")
@MainActor
struct DayContextCardCopyTests {

    /// Both directions of every eligible metric, at a handful of spans.
    private var everySentence: [DayDeviation.Standout] {
        var out: [DayDeviation.Standout] = []
        for metric in DayDeviation.eligibleMetrics {
            for z in [2.4, -2.4] {
                for span in [7, 11, 20, 43, 312] {
                    out.append(DayDeviation.Standout(
                        metric: metric,
                        value: metric == .sleepHours ? 8.03 : (metric == .hrv ? 71 : 14.4),
                        z: z,
                        daysSinceMoreExtreme: span,
                        historyDays: 400
                    ))
                }
            }
        }
        return out
    }

    /// Every authored string the card prints for one standout, lowercased, as one
    /// haystack.
    ///
    /// The sweep used to concatenate the figure and the sentence at each call
    /// site, which meant adding the title would have covered it in whichever
    /// tests remembered to. One helper instead: a fourth line added to the card
    /// tomorrow is swept by every rule below the moment it is added here.
    private func everyWord(_ standout: DayDeviation.Standout) -> String {
        [DayContextCopy.title(standout),
         DayContextCopy.figure(standout),
         DayContextCopy.sentence(standout)].joined(separator: " ").lowercased()
    }

    /// Nothing causal, clinical, population-relative, instructional, or promissory.
    private let forbidden = [
        // Causal — the card sits after a rating and must not explain it.
        "because", "causes", "caused", "due to", "leads to", "makes you", "results in",
        "the reason", "explains why", "which is why", "drives", "triggers", "boosts",
        "improves", "helps", "hurts", "effect of", "impact of", "influences",
        // Clinical — this is not a reading of anybody's health.
        "stress", "mood", "energy levels", "intensity", "burnout", "fatigue",
        "healthy", "unhealthy",
        // Population — every comparison here is against the person's own record.
        "average", "most people", "others", "normal", "typical", "benchmark",
        "the norm", "studies", "research", "people who",
        // Instruction — the app does not know what anybody should do.
        "you should", "try", "consider", "avoid", "prioritise", "schedule",
        "recommend", "make sure", "aim to",
        // Oblique prior leakage — "unusually" smuggles in a distribution we never
        // measured.
        "unusually", "rare", "unlike most",
        // Promises about what is coming.
        "yet", "soon", "more data", "unlock", "locked",
    ]

    @Test("No authored string on the card is causal, clinical or prescriptive")
    func copyIsClean() {
        for standout in everySentence {
            let text = everyWord(standout)
            for word in forbidden {
                #expect(!text.contains(word), Comment(rawValue: "\"\(text)\" contains \"\(word)\""))
            }
        }
    }

    @Test("No metric is ever called good or bad")
    func noVerdicts() {
        let verdicts = ["good", "bad", "better", "worse", "best", "worst", "poor", "great", "ideal", "optimal"]
        for standout in everySentence {
            let text = everyWord(standout)
            for verdict in verdicts {
                #expect(!text.contains(verdict), Comment(rawValue: "\"\(text)\" contains \"\(verdict)\""))
            }
        }
    }

    /// The card is byte-identical whatever was rated, which it manages by not
    /// knowing. Nothing in the copy may name a session or a score.
    @Test("The copy cannot mention the rating or the session")
    func nothingAboutTheRating() {
        let ratingWords = ["rated", "rating", "session", "5/5", "out of five", "you felt", "your rating"]
        for standout in everySentence {
            let text = everyWord(standout)
            for word in ratingWords {
                #expect(!text.contains(word), Comment(rawValue: "\"\(text)\" contains \"\(word)\""))
            }
        }
    }

    /// The title is the one line on the card that is not a sentence about the
    /// day, and that is what makes it safe to add. A metric name states no
    /// relationship between anything and anything, so none of the sweeps above
    /// have anything to catch — but it is still authored somewhere, and this
    /// pins where.
    @Test("The title is the metric's own name, not text written for the card")
    func titleIsTheMetricsOwnName() {
        for metric in DayDeviation.eligibleMetrics {
            let standout = DayDeviation.Standout(
                metric: metric, value: 8, z: 2.4, daysSinceMoreExtreme: 11, historyDays: 400)
            #expect(DayContextCopy.title(standout) == metric.title)
            #expect(!DayContextCopy.title(standout).isEmpty)
        }
        #expect(DayContextCopy.title(DayDeviation.Standout(
            metric: .sleepHours, value: 8, z: 2.4, daysSinceMoreExtreme: 11, historyDays: 400))
            == "Time asleep")
    }

    /// The card's governing rule, re-checked at the line most likely to break it.
    /// A title that varied with direction would be the first content on the card
    /// that depended on the day rather than on the metric.
    @Test("The title does not change with the direction of the day")
    func titleIsIndependentOfDirection() {
        for metric in DayDeviation.eligibleMetrics {
            func title(z: Double, span: Int) -> String {
                DayContextCopy.title(DayDeviation.Standout(
                    metric: metric, value: 8, z: z, daysSinceMoreExtreme: span, historyDays: 400))
            }
            #expect(title(z: 2.4, span: 7) == title(z: -2.4, span: 312))
        }
    }

    @Test("Every card carries the metric's own caveat")
    func caveatIsNeverAuthoredHere() {
        for metric in DayDeviation.eligibleMetrics {
            #expect(!metric.caveat.isEmpty)
        }
    }

    @Test("Figures read in the metric's own unit")
    func figuresAreFormatted() {
        func figure(_ metric: HealthMetric, _ value: Double) -> String {
            DayContextCopy.figure(DayDeviation.Standout(
                metric: metric, value: value, z: 2, daysSinceMoreExtreme: 11, historyDays: 40))
        }
        #expect(figure(.sleepHours, 8.033) == "8h 02m")
        #expect(figure(.sleepHours, 0.5) == "30m")
        #expect(figure(.hrv, 71.4) == "71 ms")
        #expect(figure(.restingHeartRate, 57.6) == "58 bpm")
        #expect(figure(.respiratoryRate, 14.44) == "14.4 bpm")
    }

    @Test("Small spans are spelled, large ones are not")
    func sentencesReadAsSentences() {
        func sentence(_ metric: HealthMetric, z: Double, span: Int) -> String {
            DayContextCopy.sentence(DayDeviation.Standout(
                metric: metric, value: 8, z: z, daysSinceMoreExtreme: span, historyDays: 400))
        }
        #expect(sentence(.sleepHours, z: 2, span: 11) == "Your longest night in eleven days.")
        #expect(sentence(.sleepHours, z: -2, span: 11) == "Your shortest night in eleven days.")
        #expect(sentence(.hrv, z: 2, span: 43) == "Your highest heart rate variability in 43 days.")
        #expect(sentence(.restingHeartRate, z: -2, span: 9) == "Your lowest resting heart rate in nine days.")
        #expect(sentence(.respiratoryRate, z: 2, span: 20) == "Your fastest breathing in twenty days.")
        #expect(sentence(.respiratoryRate, z: -2, span: 20) == "Your slowest breathing in twenty days.")
    }
}
