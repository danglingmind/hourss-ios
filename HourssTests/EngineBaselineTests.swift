import Testing
import Foundation
@testable import Hourss

/// What the current engine does when handed people whose truth is known.
///
/// This is a baseline, not a wish list. Where the engine is right, the test passes
/// and locks the behaviour in. Where it is wrong, the test states the *correct*
/// expectation and marks it as a known issue — so the defect is recorded in code
/// rather than prose, and the test starts failing the moment engine v2 fixes it.
@Suite("Current engine, against known truth")
@MainActor
struct EngineBaselineTests {

    private func insights(for person: SyntheticCohort.Person) -> [Insight] {
        InsightBuilder.build(
            sessions: person.sessions,
            reflections: person.reflections,
            activities: person.activities,
            healthByDay: person.healthByDay
        )
    }

    private func visible(for person: SyntheticCohort.Person) -> [Insight] {
        insights(for: person).filter { $0.band != .internalOnly }
    }

    // MARK: - What it gets right

    @Test("Finds a real afternoon slump")
    func findsAfternoonSlump() {
        let found = visible(for: SyntheticCohort.afternoonSlump)
        #expect(found.contains { $0.type == .bestTimeWindow || $0.type == .drainingTimeWindow },
                "a 1.2-point slump across 90 days should be found; got \(found.map(\.type.rawValue))")
    }

    @Test("Finds a real activity drain")
    func findsMeetingDrain() {
        let found = visible(for: SyntheticCohort.meetingDrain)
        #expect(found.contains { $0.type == .activityDrain || $0.type == .activityEnergizer },
                "a 1.3-point meeting drain should be found; got \(found.map(\.type.rawValue))")
    }

    // MARK: - What it gets wrong

    @Test("Says nothing about a person with no pattern")
    func staysQuietOnNoise() {
        let found = visible(for: SyntheticCohort.flatline)
        withKnownIssue("""
            The confidence formula has a floor. `42 + gap * 22 + volume * 30` returns \
            72 — an 'Emerging pattern' — whenever both sides have 12 or more rated \
            sessions, even when the gap is exactly zero. Volume alone therefore \
            manufactures confidence, so a person with no pattern cannot get a quiet \
            feed. Fixed by layer 1 (Cliff's delta with a day-clustered interval, \
            which spans zero here) and layer 2 (false-discovery correction).
            """) {
            #expect(found.isEmpty, Comment(rawValue:
                    "noise produced \(found.count) claims: " +
                    found.map { "\($0.type.rawValue)@\($0.confidence)" }.joined(separator: ", ")))
        }
    }

    @Test("Says 'not yet' when a real effect has too little evidence")
    func staysQuietOnThinEvidence() {
        let person = SyntheticCohort.shortHistory
        let found = visible(for: person)
        withKnownIssue("""
            Eighteen days and a couple of dozen rated sessions is not enough to \
            support a claim, but nothing in the engine scales confidence to the \
            width of the estimate — only to a capped session count. There is no \
            path by which it answers 'not yet'.
            """) {
            #expect(found.isEmpty, Comment(rawValue:
                    "thin evidence produced \(found.count) claims: " +
                    found.map { "\($0.type.rawValue)@\($0.confidence)" }.joined(separator: ", ")))
        }
    }

    @Test("Confidence reflects evidence, not volume")
    func confidenceTracksEvidence() {
        let real = visible(for: SyntheticCohort.afternoonSlump)
            .filter { $0.type == .bestTimeWindow || $0.type == .drainingTimeWindow }
            .map(\.confidence).max() ?? 0
        let noise = visible(for: SyntheticCohort.flatline).map(\.confidence).max() ?? 0

        withKnownIssue("""
            A true 1.2-point effect and pure noise should not score alike. They do, \
            because volume contributes up to 30 points independently of whether \
            there is any difference to be confident about.
            """) {
            #expect(real > noise + 15,
                    "real effect scored \(real), noise scored \(noise) — barely distinguishable")
        }
    }

    @Test("Under-reported drains are understated, and nothing says so")
    func missingnessIsInvisible() throws {
        let person = SyntheticCohort.skipsTheBadOnes
        let found = visible(for: person)
        let claim = found.first { $0.type == .activityDrain }

        // The engine may or may not find it; what matters is that if it does, the
        // measured gap understates the planted one and no caveat mentions why.
        if let claim {
            let measured = abs(claim.evidence.baselineValue - claim.evidence.comparisonValue)
            #expect(measured < 1.4,
                    "expected the measured gap to understate the planted 1.4")
            #expect(!claim.caveat.lowercased().contains("unrated"),
                    "caveat unexpectedly mentions unrated sessions — has this been fixed?")
        }
    }

    // MARK: - What it cannot see at all

    @Test("Cannot tell a walked meeting from an intense one")
    func cannotSeparateMovement() {
        let still = visible(for: SyntheticCohort.stillMeetings)
        let walking = visible(for: SyntheticCohort.walkingMeetings)

        // Neither person's heart rate reaches the engine: `HealthMetric` has no
        // raw heart-rate case, so the two are indistinguishable by construction.
        let bodyClaims = (still + walking).filter { $0.type == .bodyContext }
        #expect(!bodyClaims.contains { $0.statement.lowercased().contains("heart rate") &&
                                       $0.statement.lowercased().contains("meeting") },
                "the engine should not be claiming anything about meetings and heart rate yet")
    }

    @Test("Every visible claim carries evidence that matches its statement")
    func evidenceIsConsistent() throws {
        for person in SyntheticCohort.everyone {
            for insight in visible(for: person) {
                #expect(insight.evidence.comparisonCount > 0, "\(person.name): empty comparison group")
                #expect(insight.evidence.baselineCount > 0, "\(person.name): empty baseline group")
                #expect(insight.evidence.sessionIds.count ==
                        insight.evidence.comparisonCount + insight.evidence.baselineCount,
                        Comment(rawValue: "\(person.name): \(insight.type.rawValue) cites " +
                        "\(insight.evidence.sessionIds.count) sessions for " +
                        "\(insight.evidence.comparisonCount)+\(insight.evidence.baselineCount)"))
            }
        }
    }
}
