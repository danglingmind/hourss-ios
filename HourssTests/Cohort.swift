import Foundation
@testable import Hourss

/// The cohort.
///
/// Each person isolates one question. Together they cover both directions of
/// correctness: four carry a real effect the engine ought to find, and three carry
/// none — or one it should refuse to explain — which is where a pattern engine
/// actually fails.
extension SyntheticCohort {

    /// A genuine afternoon slump. The simplest true thing there is.
    static var afternoonSlump: Person {
        make(.init(name: "Afternoon slump", seed: 0x51A9,
                   truth: .init(
                       planted: [.timeWindow(better: .morning, worse: .afternoon, delta: 1.2)],
                       rationale: "A clear, large, real time-of-day effect. If this is missed, nothing else matters.")))
    }

    /// Nothing is true. Ratings vary because ratings vary.
    ///
    /// This is the most important person in the cohort. A person with no pattern
    /// must produce no claim, and that is the property no amount of real data can
    /// check — real data never tells you it had nothing in it.
    static var flatline: Person {
        make(.init(name: "Flatline", seed: 0xF1A7, noiseSD: 0.85,
                   truth: .init(
                       planted: [],
                       forbidden: [.anyVisibleClaim],
                       rationale: "Pure noise. Any visible claim here is a false positive by construction.")))
    }

    /// Meetings genuinely drain this person.
    static var meetingDrain: Person {
        make(.init(name: "Meeting drain", seed: 0x33E1,
                   truth: .init(
                       planted: [.activityEffect(named: "Meetings", delta: -1.3)],
                       rationale: "A real activity effect, to check the engine attributes it to the activity rather than the hour.")))
    }

    /// A real effect, but only three weeks of it.
    ///
    /// The engine should stay quiet — not because the effect is absent, but
    /// because there is not yet enough to tell. "Not yet" is a legitimate answer
    /// and the current confidence formula has no way to give it.
    static var shortHistory: Person {
        make(.init(name: "Short history", seed: 0x21D5, days: 18, sessionsPerDay: 1...2,
                   truth: .init(
                       planted: [.timeWindow(better: .morning, worse: .afternoon, delta: 1.1)],
                       forbidden: [.anyVisibleClaim],
                       rationale: "Real effect, too little evidence. Tests whether the engine can say 'not yet'.")))
    }

    /// Heart rate rises in meetings and the person is sitting still.
    static var stillMeetings: Person {
        make(.init(name: "Still meetings", seed: 0x8B12,
                   truth: .init(
                       planted: [.heartRate(activity: "Meetings", bpm: 11, movement: false)],
                       rationale: "Elevated heart rate with no movement behind it — the case layer 3 should surface.")))
    }

    /// Heart rate rises in meetings because the person walks through them.
    ///
    /// The physiological reading is identical to `stillMeetings`. Only the step
    /// data separates them, which is the entire argument for the movement
    /// residual — and the reason a heart-rate-only engine would be wrong here.
    static var walkingMeetings: Person {
        make(.init(name: "Walking meetings", seed: 0x8B13,
                   truth: .init(
                       planted: [.heartRate(activity: "Meetings", bpm: 11, movement: true)],
                       forbidden: [.claim(.bodyContext)],
                       rationale: "Same heart rate as Still meetings, explained by walking. Must not read as intensity.")))
    }

    /// A real drain, but the person stops rating sessions when they go badly.
    ///
    /// The observable ratings are therefore biased upward exactly where the effect
    /// lives. Nothing in the engine notices, and the BRD names this as unsolved —
    /// this person makes the size of the distortion measurable.
    static var skipsTheBadOnes: Person {
        make(.init(name: "Skips the bad ones", seed: 0x5C1B, skipsLowRatings: true,
                   truth: .init(
                       planted: [.activityEffect(named: "Admin", delta: -1.4)],
                       rationale: "Informative missingness: the drain is real but under-reported, so the measured gap understates it.")))
    }

    /// Everyone, for suites that sweep the cohort.
    static var everyone: [Person] {
        [afternoonSlump, flatline, meetingDrain, shortHistory,
         stillMeetings, walkingMeetings, skipsTheBadOnes]
    }
}
