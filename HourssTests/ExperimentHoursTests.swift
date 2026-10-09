import Foundation
import Testing
@testable import Hourss

/// That an hour nobody logged becomes an offer, and says nothing it has not earned.
@Suite("Hour-led proposals")
struct ExperimentHoursTests {

    private let calendar = Calendar.current

    private func rows(_ person: SyntheticCohort.Person) -> [EngineObservation] {
        ObservationBuilder.rows(
            sessions: person.sessions,
            reflections: person.reflections,
            activities: person.activities,
            healthByDay: person.healthByDay,
            residuals: [:],
            workdays: Profile().workdays
        )
    }

    private func offers(
        _ person: SyntheticCohort.Person,
        priorities: [Priority] = [.focus],
        wake: Int? = nil
    ) -> [ExperimentDesign.Proposal] {
        let observations = rows(person)
        return ExperimentHours.proposals(
            for: priorities,
            shape: RatingShape.fit(observations),
            observations: observations,
            wake: wake
        )
    }

    // MARK: - The offer exists, and is about the right hour

    @Test("The interpolator is offered the hour they have never logged")
    func interpolatorIsOffered() throws {
        let proposal = try #require(offers(SyntheticCohort.interpolator).first)
        #expect(proposal.premise.contains("7am"), Comment(rawValue: proposal.premise))
        #expect(proposal.standing == .starter,
                "nothing has been measured about how this band's sessions read")
    }

    /// The person whose record says nothing about the morning gets nothing from this
    /// source — and that is the design, not a shortfall.
    ///
    /// `RatingShape` refuses any hour without evidence on both sides, so somebody
    /// logging only in the evening falls through to the sources below, which exist
    /// for exactly them: their body still knows something and the prior still has a
    /// question worth asking.
    @Test("The extrapolator is offered nothing from their own ratings")
    func extrapolatorGetsNothing() {
        #expect(offers(SyntheticCohort.extrapolator).isEmpty)
    }

    @Test("An hour somebody already logs is never offered back to them")
    func loggedHoursAreNotOffered() throws {
        let person = SyntheticCohort.interpolator
        let logged = ExperimentHours.loggedHours(in: rows(person))
        #expect(logged.contains(6) && logged.contains(8))

        let shape = RatingShape.fit(rows(person))
        let candidates = ExperimentHours.candidates(shape: shape, used: logged, wake: nil)
        #expect(!candidates.map(\.hour).contains(where: logged.contains),
                Comment(rawValue: "offered an hour they already use: \(candidates.map(\.hour))"))
        #expect(candidates.first?.hour == 7)
    }

    @Test("An hour before somebody is up is never offered")
    func wakingIsRespected() {
        let person = SyntheticCohort.interpolator
        let shape = RatingShape.fit(rows(person))
        let logged = ExperimentHours.loggedHours(in: rows(person))

        let early = ExperimentHours.candidates(shape: shape, used: logged, wake: 5 * 60)
        #expect(early.first?.hour == 7)

        // Somebody who gets up at nine may not be told to put a block at seven.
        let late = ExperimentHours.candidates(shape: shape, used: logged, wake: 9 * 60)
        #expect(!late.map(\.hour).contains(7), Comment(rawValue: "\(late.map(\.hour))"))
    }

    @Test("A priority no time-of-day test can serve is skipped")
    func onlyTimeOfDayPriorities() {
        // `sleep` maps to `sleepContext`, which no band hypothesis serves.
        #expect(offers(SyntheticCohort.interpolator, priorities: [.sleep]).isEmpty)
    }

    // MARK: - What the sentences may say

    /// The copy sweep, over every string this source can produce.
    ///
    /// The premise is built from a smoother that survived no correction, so the one
    /// thing it may not do is read as a finding. `NarrationGuard` catches the
    /// vocabulary; the hedge and the second sentence carry the rest, and both are
    /// asserted here because a guard cannot see a sentence that is plain in its words
    /// and still describes machinery.
    @Test("Nothing in an hour-led offer claims more than it has")
    func theCopySweeps() throws {
        let proposal = try #require(offers(SyntheticCohort.interpolator).first)

        // The hour is the one figure these sentences are allowed, and it is the whole
        // of what this source adds — so it is permitted by name rather than by
        // turning the figure check off, which would also wave through a quoted
        // estimate.
        let clock = ExperimentCopy.clockHour(7)
        let allowed = Set(clock.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty })

        for sentence in [proposal.premise, proposal.change, proposal.caveat] {
            switch NarrationGuard.offence(in: sentence, allowingFigures: allowed) {
            // `instruction` is lifted and only `instruction`, as everywhere else a
            // proposal is swept — `PRD-TESTS-PRESENCE.md` item 8, and
            // `ExperimentVitalsTests` does the same. A proposal's whole job is to ask
            // somebody to do something, and the registry's own time-of-day caveat
            // says "whatever you tend to schedule then", which is descriptive.
            case .none, .instruction:
                continue
            case let .some(offence):
                Issue.record(Comment(rawValue: "\(offence) in: \(sentence)"))
            }
        }

        // Hedged, and said to be unsettled. Without both, a smoothed average reads as
        // a measured claim about their mornings.
        #expect(proposal.premise.contains("so far"))
        #expect(proposal.premise.contains("Nothing you have logged says yet"))
    }

    /// `PRD-HOURS.md` item 14 — no figure from the curve reaches any string.
    ///
    /// The curve's two numbers are an estimate on the 1–5 scale and a support weight
    /// in day-equivalents. Neither is evidence, neither survived a correction, and
    /// quoting either would turn a reason for asking into an answer. The hour is the
    /// only thing that crosses from the curve into a sentence.
    @Test("No number the curve produced reaches a sentence")
    func noCurveFigureIsQuoted() throws {
        let observations = rows(SyntheticCohort.interpolator)
        let shape = RatingShape.fit(observations)
        let proposal = try #require(offers(SyntheticCohort.interpolator).first)
        let sentences = proposal.premise + " " + proposal.change + " " + proposal.caveat

        for hour in shape.hours {
            // Two decimals and one, since either would be a plausible way to print it.
            for figure in [String(format: "%.2f", hour.estimate),
                           String(format: "%.1f", hour.estimate),
                           String(format: "%.0f", hour.support),
                           String(format: "%.1f", hour.support)] {
                #expect(!sentences.contains(figure), Comment(rawValue:
                    "a curve figure reached the copy: \(figure) in \(sentences)"))
            }
        }
    }

    // MARK: - Its place in the chain

    @Test("One offer per priority, and never two for one question")
    func onePerPriority() {
        let proposals = offers(SyntheticCohort.interpolator, priorities: [.focus, .balance])
        let priorities = proposals.map(\.priority)
        #expect(priorities.count == Set(priorities).count)
        let ids = proposals.map(\.hypothesisId)
        #expect(ids.count == Set(ids).count, "one hypothesis may not be offered twice")
    }

    @Test("A priority already served keeps what it had")
    func completingDefersToWhatExists() throws {
        let observations = rows(SyntheticCohort.interpolator)
        let existing = try #require(
            ExperimentHours.proposals(for: [.focus],
                                      shape: RatingShape.fit(observations),
                                      observations: observations).first)

        let completed = ExperimentHours.completing(
            [existing],
            priorities: [.focus],
            shape: RatingShape.fit(observations),
            observations: observations)

        #expect(completed.count == 1, "focus was already served and may not be served twice")
    }
}
