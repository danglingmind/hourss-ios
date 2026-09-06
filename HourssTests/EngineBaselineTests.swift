import Testing
import Foundation
@testable import Hourss

/// What engine v2 must do when handed people whose truth is known.
///
/// These were written against the old engine first, with the correct expectations
/// stated and three of them marked as known issues, so the defects lived in code
/// rather than prose. Those markers are gone: what follows is a plain acceptance
/// suite, and the numbers in the comments are what the old engine actually
/// produced on the same fixtures.
@Suite("Engine v2, against known truth")
@MainActor
struct EngineBaselineTests {

    private func rows(for person: SyntheticCohort.Person) -> [EngineObservation] {
        ObservationBuilder.rows(
            sessions: person.sessions,
            reflections: person.reflections,
            activities: person.activities,
            healthByDay: person.healthByDay
        )
    }

    private func insights(for person: SyntheticCohort.Person,
                          priorities: [Priority] = []) -> [Insight] {
        Engine.run(EngineInput(observations: rows(for: person), priorities: priorities))
    }

    private func visible(for person: SyntheticCohort.Person) -> [Insight] {
        insights(for: person).filter { $0.band != .internalOnly }
    }

    // MARK: - Finding what is there

    @Test("Finds a real afternoon slump")
    func findsAfternoonSlump() {
        let found = visible(for: SyntheticCohort.afternoonSlump)
        #expect(found.contains { $0.type == .bestTimeWindow || $0.type == .drainingTimeWindow },
                "a 1.2-point slump across 90 days should be found")
    }

    @Test("Finds a real activity drain")
    func findsMeetingDrain() {
        let found = visible(for: SyntheticCohort.meetingDrain)
        #expect(found.contains { $0.type == .activityDrain || $0.type == .activityEnergizer },
                "a 1.3-point meeting drain should be found")
    }

    // MARK: - Not finding what is not there
    //
    // The half that matters. Anything can find patterns in noise; the only way to
    // know whether this does is to hand it noise and watch.

    @Test("Says nothing about a person with no pattern")
    func staysQuietOnNoise() {
        let found = visible(for: SyntheticCohort.flatline)
        #expect(found.isEmpty, Comment(rawValue:
                "noise produced \(found.count) claims: " +
                found.map { "\($0.type.rawValue)@\($0.confidence)" }.joined(separator: ", ")))
    }

    @Test("Says 'not yet' when a real effect has too little evidence")
    func staysQuietOnThinEvidence() {
        let found = visible(for: SyntheticCohort.shortHistory)
        #expect(found.isEmpty, Comment(rawValue:
                "thin evidence produced \(found.count) claims: " +
                found.map { "\($0.type.rawValue)@\($0.confidence)" }.joined(separator: ", ")))
    }

    /// The old engine scored a genuine 1.2-point effect and pure noise at exactly
    /// 74 apiece — the confidence number carried no information about whether
    /// there was anything there.
    @Test("A real effect outscores noise")
    func confidenceTracksEvidence() {
        let real = visible(for: SyntheticCohort.afternoonSlump)
            .filter { $0.type == .bestTimeWindow || $0.type == .drainingTimeWindow }
            .map(\.confidence).max() ?? 0
        let noise = visible(for: SyntheticCohort.flatline).map(\.confidence).max() ?? 0
        #expect(real > noise + 15, Comment(rawValue:
                "real effect scored \(real), noise scored \(noise)"))
    }

    /// The finding that redirected the design: the old engine produced *four*
    /// claims from eighteen days and *one* from ninety days of noise. Less
    /// evidence yielded more confident output, because a small sample makes large
    /// gaps by chance and the formula rewarded the gap.
    @Test("Claim count cannot rise as evidence falls")
    func lessEvidenceIsNeverMoreConfident() {
        let thin = visible(for: SyntheticCohort.shortHistory).count
        let noisy = visible(for: SyntheticCohort.flatline).count
        let real = visible(for: SyntheticCohort.afternoonSlump).count
        #expect(thin <= real, Comment(rawValue:
                "18 days produced \(thin) claims against \(real) from 90 days of real effect"))
        #expect(noisy <= real)
    }

    // MARK: - Honesty of the evidence line

    @Test("The window reported is the window the data covers")
    func windowIsHonest() {
        // The old engine printed "past 6 weeks" on eighteen days of history.
        for insight in visible(for: SyntheticCohort.shortHistory) + visible(for: SyntheticCohort.afternoonSlump) {
            #expect(!insight.evidence.windowDescription.isEmpty)
            #expect(!insight.evidence.windowDescription.contains("6 weeks")
                    || insight.evidence.sessionIds.count > 20,
                    "a six-week claim needs more than a handful of sessions behind it")
        }
    }

    @Test("Every visible claim carries evidence that matches its statement")
    func evidenceIsConsistent() {
        for person in SyntheticCohort.everyone {
            for insight in visible(for: person) {
                #expect(insight.evidence.comparisonCount > 0, "empty comparison group")
                #expect(insight.evidence.baselineCount > 0, "empty baseline group")
                #expect(insight.evidence.sessionIds.count ==
                        insight.evidence.comparisonCount + insight.evidence.baselineCount,
                        Comment(rawValue: "\(person.name): \(insight.type.rawValue) cites " +
                        "\(insight.evidence.sessionIds.count) sessions for " +
                        "\(insight.evidence.comparisonCount)+\(insight.evidence.baselineCount)"))
            }
        }
    }

    @Test("No claim states a rule about the person, or reads as medical")
    func copyStaysWithinBounds() {
        let forbidden = ["stress", "intense", "elevated", "you always", "you never",
                         "diagnos", "disorder", "unhealthy", "average person", "most people"]
        for person in SyntheticCohort.everyone {
            for insight in visible(for: person) {
                let text = (insight.statement + " " + insight.caveat).lowercased()
                for word in forbidden {
                    #expect(!text.contains(word), Comment(rawValue:
                            "\(person.name): \"\(insight.statement)\" contains \"\(word)\""))
                }
                #expect(!insight.caveat.isEmpty, "every claim carries its limit")
            }
        }
    }

    // MARK: - Identity survives recomputation

    /// Granting Health access used to empty whatever the person had saved, because
    /// every rebuild minted fresh UUIDs.
    @Test("Insight identity is stable across runs")
    func identityIsStable() {
        let person = SyntheticCohort.afternoonSlump
        let first = insights(for: person).map(\.id).sorted { $0.uuidString < $1.uuidString }
        let second = insights(for: person).map(\.id).sorted { $0.uuidString < $1.uuidString }
        #expect(first == second, "the same data produced different insight ids")
        #expect(!first.isEmpty)
    }

    @Test("Saved and hidden survive a rebuild")
    func statusSurvivesRebuild() throws {
        let person = SyntheticCohort.afternoonSlump
        let store = HourssStore()
        store.activities = person.activities
        store.sessions = person.sessions
        store.reflections = person.reflections
        store.rebuildInsights()

        let target = try #require(store.insights.first)
        store.setStatus(.saved, for: target.id)

        // Exactly the event that used to wipe it.
        store.applyHealthContext(person.healthByDay)

        let after = store.insights.first { $0.id == target.id }
        #expect(after?.status == .saved,
                "saved state did not survive applying health context")
    }
}
