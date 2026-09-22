import Testing
import Foundation
import SwiftUI
@testable import Hourss

/// The words the app is allowed to say about a movement-adjusted heart rate.
///
/// Two rules are being held here and neither is a matter of taste.
///
/// **The gate.** `Physiology.Reading.exceedsUncertainty` is documented as the
/// line between a finding and a number — "anything that does not is a number,
/// not a finding, and must not be shown as one". `SessionResidual.init?` is the
/// only way to make a value any surface can render, so the gate is tested once
/// here rather than at every call site, which is the point of putting it there.
///
/// **The register.** `Outcome.heartRateResidual.higherIsBetter` is nil on
/// purpose: a heart rate above what movement explains is not "bad", and calling
/// it so would be a medical claim. `Physiology` says the same about its own
/// output — never stress, intensity, effort, or emotion — and `PhysiologyTests`
/// already sweeps the movement contexts for exactly that. This is the same sweep
/// one layer up, over the copy a person actually receives, because the layer
/// below being clean does not stop a view from adding a verdict on top of it.
///
/// `@MainActor` because two of these build views. `TitledFigure` carries an
/// `@Environment`, and a `DynamicProperty` initialised off the main actor traps —
/// the same reason `ReadoutOrderTests` is annotated.
@Suite("Residual copy")
@MainActor
struct ResidualCopyTests {

    /// A reading with the two numbers that matter chosen, and the rest plausible.
    private func reading(residual: Double,
                         uncertainty: Double,
                         cadence: Double = 4) -> Physiology.Reading {
        Physiology.Reading(
            windowId: UUID(),
            observed: 70 + residual,
            expected: 70,
            explainedByMovement: 1,
            residual: residual,
            cadence: cadence,
            cadenceBin: .containing(cadence),
            sampleCount: 22,
            uncertainty: uncertainty
        )
    }

    // MARK: - The gate

    /// The whole reason `SessionResidual` has a failable init and no other.
    @Test("A residual inside its own error bar cannot be built")
    func insideTheErrorBarIsNotShowable() {
        // Comfortably inside.
        #expect(SessionResidual(reading(residual: 2, uncertainty: 6)) == nil)
        // Exactly on it. `exceedsUncertainty` is a strict inequality, and equality
        // is a residual the size of the noise it sits in.
        #expect(SessionResidual(reading(residual: 6, uncertainty: 6)) == nil)
        // Negative, too — the gate is on the magnitude, not on the direction.
        #expect(SessionResidual(reading(residual: -3, uncertainty: 6)) == nil)
        // And nothing at all is nothing to show.
        #expect(SessionResidual(nil) == nil)
    }

    @Test("A residual that clears its error bar carries a magnitude and a direction")
    func outsideTheErrorBarIsShowable() throws {
        let higher = try #require(SessionResidual(reading(residual: 7.4, uncertainty: 3)))
        #expect(higher.bpm == 7)
        #expect(higher.isHigher)

        let lower = try #require(SessionResidual(reading(residual: -7.4, uncertainty: 3)))
        #expect(lower.bpm == 7, "the magnitude is unsigned; the direction is a word")
        #expect(!lower.isHigher)
    }

    /// "0 bpm above expected" is a sentence that contradicts itself. The error
    /// bar's own floor should make it unreachable; the clamp is there so one
    /// change to the floor cannot ship it.
    @Test("A shown residual is never zero bpm")
    func neverZeroBpm() throws {
        let residual = try #require(SessionResidual(reading(residual: 0.4, uncertainty: 0.1)))
        #expect(residual.bpm >= 1)
        #expect(!ResidualCopy.figure(residual).hasPrefix("0 "))
    }

    /// The movement half is `CadenceBin`'s, verbatim. A second vocabulary for the
    /// same idea is a second place for a cause to be named — which is the exact
    /// thing that property exists to prevent.
    @Test("The movement context is the physiology layer's own words")
    func movementContextIsNotRewritten() throws {
        for bin in Physiology.CadenceBin.allCases {
            let cadence: Double = [0, 10, 40, 80, 140][bin.rawValue]
            let residual = try #require(SessionResidual(reading(residual: 9, uncertainty: 3, cadence: cadence)))
            #expect(residual.movementContext == Physiology.CadenceBin.containing(cadence).context)
            #expect(ResidualCopy.sentence(residual).contains(residual.movementContext))
        }
    }

    // MARK: - The register

    /// Every string any surface can say about a residual, in one bag.
    private func allCopy() throws -> String {
        var parts: [String] = [ResidualCopy.title]
        for direction in [1.0, -1.0] {
            for cadence in [0.0, 10, 40, 80, 140] {
                let residual = try #require(
                    SessionResidual(reading(residual: direction * 9, uncertainty: 3, cadence: cadence)))
                parts.append(ResidualCopy.figure(residual))
                parts.append(ResidualCopy.sentence(residual))
                // The card routes through `DayContextCopy`, so sweep what the card
                // actually prints rather than trusting that it forwards.
                let content = DayContextCard.Content.residual(residual)
                parts.append(DayContextCopy.title(content))
                parts.append(DayContextCopy.figure(content))
                parts.append(DayContextCopy.sentence(content))
            }
        }
        return parts.joined(separator: " ").lowercased()
    }

    /// `PhysiologyTests.outputCarriesNoJudgement`'s list, applied to the copy
    /// rather than to the movement contexts, plus the words a *view* is tempted
    /// by that a data layer never is.
    ///
    /// The caveat is deliberately not in this bag. It is not copy this app
    /// authors — it is `HypothesisRegistry`'s caveat for this outcome, held to
    /// that text by `caveatMatchesTheRegistry` below — and the one banned word it
    /// contains appears inside a negation: "heart rate moves with more than
    /// effort" denies that effort is the explanation, which is the opposite of
    /// the claim this sweep exists to catch. Sweeping it would force the app to
    /// fork the engine's wording, which is the drift `DayContextCard` warns
    /// about at length.
    @Test("The copy states a number and a movement context, never a verdict")
    func copyCarriesNoJudgement() throws {
        let words = try allCopy()

        // Verbatim from `PhysiologyTests`.
        for banned in ["stress", "intense", "anxious", "calm", "effort", "strain", "tense"] {
            #expect(!words.contains(banned), Comment(rawValue:
                "residual copy must not imply a cause: \"\(banned)\" in \"\(words)\""))
        }

        // A direction is allowed to be a direction and nothing else. There is no
        // good end of this scale — `Outcome.heartRateResidual.higherIsBetter` is
        // nil — so a verdict here is a medical opinion, not a turn of phrase.
        for verdict in ["better", "worse", "good", "bad", "great", "poor",
                        "harder", "easier", "healthy", "unhealthy",
                        "recovery", "recovered", "elevated", "spike"] {
            #expect(!words.contains(verdict), Comment(rawValue:
                "residual copy contains the verdict \"\(verdict)\": \"\(words)\""))
        }

        // No causation, no population, no instruction — the three shapes every
        // copy sweep in this codebase bans.
        for banned in ["because", "caused", "due to", "leads to", "results in",
                       "the reason", "explains why", "which is why", "triggers",
                       "average", "most people", "normal", "typical", "others",
                       "you should", "try to", "make sure", "consider ", "avoid"] {
            #expect(!words.contains(banned), Comment(rawValue:
                "residual copy contains \"\(banned)\": \"\(words)\""))
        }
    }

    /// `HypothesisRegistry` phrases this outcome with "have run" while every
    /// other outcome gets "have felt" — `Narration.parts` switches on exactly
    /// that. A heart rate is a thing that ran; borrowing the feeling verb would
    /// turn a measurement into a report of an inner state.
    @Test("The sentence uses the running verb, never the feeling one")
    func registerMatchesTheRegistry() throws {
        let words = try allCopy()
        #expect(words.contains("ran"))
        for feelingVerb in ["felt", "feel", "feeling"] {
            #expect(!words.contains(feelingVerb), Comment(rawValue:
                "\"\(feelingVerb)\" in residual copy — that is the other outcome's verb"))
        }
    }

    /// The baseline is this person's own, and saying so is what stops a reader
    /// supplying a population comparison the app never made. The curve is fitted
    /// per person and never across people, precisely because "is this heart rate
    /// high for a human" is a medical question this product does not ask.
    @Test("The sentence says whose baseline it is")
    func baselineIsNamedAsTheirOwn() throws {
        let residual = try #require(SessionResidual(reading(residual: 9, uncertainty: 3)))
        #expect(ResidualCopy.sentence(residual).contains("your own"))
    }

    /// Direction is a word, not a glyph. A leading "+" would put the entire
    /// meaning of the figure into one character, which fails for the same reason
    /// colour-only encoding does.
    @Test("Direction is carried by a word")
    func directionIsAWord() throws {
        let higher = try #require(SessionResidual(reading(residual: 9, uncertainty: 3)))
        let lower = try #require(SessionResidual(reading(residual: -9, uncertainty: 3)))
        #expect(ResidualCopy.figure(higher).contains("above"))
        #expect(ResidualCopy.figure(lower).contains("below"))
        for figure in [ResidualCopy.figure(higher), ResidualCopy.figure(lower)] {
            #expect(!figure.contains("+"))
            #expect(!figure.contains("-"))
            #expect(!figure.contains("−"))
        }
    }

    // MARK: - The caveat

    /// The deal `Narration` already strikes with the registry, applied to the
    /// caveat: the string is duplicated rather than plumbed through, because the
    /// registry only has it inside a `Hypothesis` that twelve scored sessions
    /// have to exist for, and a view cannot run the engine to find out what to
    /// say. The words must match, and this test is cheaper than the coupling.
    @Test("The caveat is the registry's own, word for word")
    func caveatMatchesTheRegistry() throws {
        let hypotheses = HypothesisRegistry.hypotheses(for: scorableObservations())
        let physiology = try #require(
            hypotheses.first { $0.outcome == .heartRateResidual },
            "the registry stopped producing a residual hypothesis; the fixture below needs updating")
        #expect(physiology.caveat == ResidualCopy.caveat, Comment(rawValue:
            "the card says \"\(ResidualCopy.caveat)\" and the engine says "
                + "\"\(physiology.caveat)\" about the same number"))
    }

    /// Enough rows for `HypothesisRegistry.physiology` to register a question:
    /// twelve carrying a residual, with at least six on each side of one
    /// activity's split.
    private func scorableObservations() -> [EngineObservation] {
        let day = Calendar.current.startOfDay(for: Date())
        return (0..<14).map { index in
            EngineObservation(
                sessionId: UUID(),
                day: day.addingTimeInterval(Double(index) * -86_400),
                startAt: day.addingTimeInterval(Double(index) * -86_400 + 36_000),
                durationMinutes: 60,
                activityName: index < 7 ? "Meetings" : "Deep work",
                activityCategory: "Work",
                timeBucket: .morning,
                durationBucket: .medium,
                isWorkday: true,
                feeling: 3,
                performance: nil,
                dayHealth: [:],
                heartRateResidual: Double(index) - 7,
                cadence: 12
            )
        }
    }

    // MARK: - The readout's order

    /// `TitledFigure`'s rule, applied to the surface that was added: a figure is
    /// not information until something has said what it is a figure of. "6 bpm
    /// above expected" is not a fact about a heart rate until the word heart rate
    /// has been spoken.
    @Test("The reading names its subject before its number")
    func readingLeadsWithItsSubject() throws {
        let residual = try #require(SessionResidual(reading(residual: 9, uncertainty: 3)))
        let titled = try #require(ResidualReading(residual).titled)

        #expect(titled.title == "Heart rate")
        #expect(titled.title.first?.isNumber != true)
        #expect(titled.spoken.hasPrefix(titled.title), Comment(rawValue:
            "spoken form does not lead with its subject: \(titled.spoken)"))
        // The number and the sentence both survive into the spoken form — a
        // combined element that drops the detail loses the movement context,
        // which is the half that keeps the number from being read as a cause.
        #expect(titled.spoken.contains("9 bpm above expected"))
        #expect(titled.spoken.contains(residual.movementContext))
    }

    /// Nothing to say draws nothing. The view takes the optional so the gate
    /// stays in one place instead of being re-checked at every call site.
    @Test("No reading means no readout")
    func absentReadingRendersNothing() {
        #expect(ResidualReading(nil).titled == nil)
    }

    /// The readout actually draws, and drawing is the one thing a value test
    /// cannot tell you.
    ///
    /// `store.physiologyReadings` is empty on a simulator — nothing calls
    /// `DebugFixture.seededFeed`, and HealthKit has no samples there — so the
    /// screenshot walkthrough can only ever show this surface *absent*. That
    /// makes the absent case well covered and the present case covered by
    /// nothing, which is the wrong way round: an empty `VStack`, a crash in
    /// layout or a view that resolves to zero height would all pass every other
    /// test in this file. Rasterising it is the cheapest honest check that the
    /// present case reaches pixels at all.
    @Test("The readout renders to something with size")
    func readingRasterises() throws {
        let residual = try #require(SessionResidual(reading(residual: 9, uncertainty: 3)))
        let renderer = ImageRenderer(content:
            ResidualReading(residual).frame(width: 360))
        let image = try #require(renderer.uiImage, "the readout drew nothing")
        #expect(image.size.width > 0)
        #expect(image.size.height > 0, "the readout resolved to zero height")
    }
}
