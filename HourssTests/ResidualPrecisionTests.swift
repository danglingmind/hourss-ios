import Foundation
import Testing
@testable import Hourss

/// That a residual measured badly does not count the same as one measured well.
///
/// The engine document raises this as §10.8: `Reading.uncertainty` widens with
/// cadence and with how few samples a window held, and it gated only what could be
/// *shown*. The residual then entered layer 2 as a plain number, so a reading
/// carried with a 12 bpm error bar and one carried with 5 counted identically in the
/// comparison.
@Suite("Residual precision")
struct ResidualPrecisionTests {

    private func analyzer(_ person: SyntheticCohort.Person) -> Physiology.Analyzer {
        let feed = Physiology.Feed(
            heartRate: person.heartRate.map { Physiology.Sample(at: $0.at, value: $0.value) },
            steps: (person.samples[.steps] ?? []).map { Physiology.Sample(at: $0.at, value: $0.value) }
        )
        return Physiology.Analyzer(feed: feed, fittingWindows: Physiology.Window.tiling(feed))
    }

    /// Readings for every session this person logged, kept and dropped.
    private func split(_ person: SyntheticCohort.Person) -> (kept: Int, total: Int) {
        let analyzer = analyzer(person)
        var kept = 0, total = 0
        for session in person.sessions {
            guard let reading = analyzer.reading(for: session) else { continue }
            total += 1
            if reading.isPreciseEnough { kept += 1 }
        }
        return (kept, total)
    }

    // MARK: - The bar

    @Test("The bar is twice the smallest difference the app will speak about")
    func theBarIsDerived() {
        // Not a new scale. `DayShape.minimumDifference` is the smallest difference
        // this app says anything about, and an error bar wider than twice it cannot
        // support a statement about a difference of that size.
        #expect(Physiology.Reading.maximumUncertainty == 2 * Physiology.DayShape.minimumDifference)
        #expect(Physiology.Reading.maximumUncertainty == 10)
    }

    // MARK: - What it keeps and what it drops

    /// It bites where uncertainty comes from movement, and nowhere else.
    ///
    /// The numbers are the record of what this costs. Somebody sitting still through
    /// their sessions loses nothing; somebody walking through most of their day loses
    /// a good deal, because a wrist reading taken at pace is the least accurate one
    /// available — `Analyzer.uncertainty` widens with cadence for exactly that reason.
    @Test("Still readings are kept whole and walked ones are thinned")
    func itBitesWhereTheNoiseIs() {
        let still = split(SyntheticCohort.stillMeetings)
        #expect(still.kept == still.total,
                Comment(rawValue: "sitting still lost readings: \(still)"))

        let walking = split(SyntheticCohort.walksEverywhere)
        #expect(walking.kept < walking.total, "a day spent walking should lose some")
    }

    /// And it may not thin them to nothing.
    ///
    /// **The guard that matters.** The people this layer was built for are the ones
    /// who walk *and* whose heart rate still runs above what the walking explains —
    /// `walksAndStrains` is that person, and they are the heaviest loser under this
    /// gate. A bar set too high would silently remove the whole case the residual
    /// exists to find, and the suite would stay green because their claim would
    /// simply stop being made.
    ///
    /// A third is the floor. It is not derived: it is the point at which this test
    /// stops being a regression guard and starts being a description of whatever the
    /// code currently does.
    @Test("A walker keeps enough readings to still be compared")
    func walkersAreNotSilenced() {
        for person in [SyntheticCohort.walksEverywhere, SyntheticCohort.walksAndStrains] {
            let (kept, total) = split(person)
            #expect(Double(kept) / Double(total) > 0.33, Comment(rawValue:
                "\(person.name) kept \(kept) of \(total) — the gate is eating the case "
                + "the layer exists for"))
            // Comfortably past what a comparison needs on each side, so the gate is
            // not quietly deciding what the engine may ask about.
            #expect(kept >= EvidenceFloor.perSide * 2,
                    Comment(rawValue: "\(person.name) kept \(kept) readings"))
        }
    }

    // MARK: - The hazard it must not become

    /// `exceedsUncertainty` may gate display and may never gate entry.
    ///
    /// Filtering the rows that reach the statistic on whether a residual clears its
    /// own error bar is selection on the *outcome*: it keeps the large residuals on
    /// both sides of every comparison and drops the small ones, which inflates every
    /// effect size measured afterwards. `isPreciseEnough` reads nothing about the
    /// residual's value, which is what makes it safe to apply first.
    ///
    /// Asserted as a property of the two definitions rather than of any call site,
    /// because the hazard is that somebody later swaps one for the other.
    @Test("The entry gate reads nothing about the residual itself")
    func theEntryGateIgnoresTheValue() {
        let wide = Physiology.Reading(
            windowId: UUID(), observed: 70, expected: 65, explainedByMovement: 0,
            residual: 5, cadence: 0, cadenceBin: .still, sampleCount: 20, uncertainty: 12)
        let tight = Physiology.Reading(
            windowId: UUID(), observed: 70, expected: 65, explainedByMovement: 0,
            residual: 5, cadence: 0, cadenceBin: .still, sampleCount: 20, uncertainty: 4)

        // Same residual, different error bars: only the error bar decides entry.
        #expect(!wide.isPreciseEnough)
        #expect(tight.isPreciseEnough)

        // And a residual of nearly nothing, measured well, is admitted — which is the
        // whole difference between the two gates. Under `exceedsUncertainty` it would
        // be refused, and refusing it is what would tilt the comparison.
        let quiet = Physiology.Reading(
            windowId: UUID(), observed: 65.2, expected: 65, explainedByMovement: 0,
            residual: 0.2, cadence: 0, cadenceBin: .still, sampleCount: 20, uncertainty: 4)
        #expect(quiet.isPreciseEnough)
        #expect(!quiet.exceedsUncertainty)
    }
}
