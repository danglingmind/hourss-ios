import Foundation
@testable import Hourss

/// The cohort.
///
/// Constants rather than computed properties, and that is load-bearing. Every
/// `Session` mints a fresh `UUID`, so a computed person handed out a different
/// set of identifiers on every access — reading `.sessions` from one access and
/// `.reflections` from another gave two people whose keys did not match, and
/// every rating silently went missing. A test written that way fails, or worse
/// passes, for a reason that has nothing to do with what it claims to check.
///
/// Each person isolates one question. Together they cover both directions of
/// correctness: five carry a real effect the engine ought to find, and four carry
/// none — or one it should refuse to explain — which is where a pattern engine
/// actually fails.
extension SyntheticCohort {

    /// A genuine afternoon slump. The simplest true thing there is.
    static let afternoonSlump: Person = make(.init(name: "Afternoon slump", seed: 0x51A9,
                   truth: .init(
                       planted: [.timeWindow(better: .morning, worse: .afternoon, delta: 1.2)],
                       rationale: "A clear, large, real time-of-day effect. If this is missed, nothing else matters.")))

    /// Nothing is true. Ratings vary because ratings vary.
    ///
    /// This is the most important person in the cohort. A person with no pattern
    /// must produce no claim, and that is the property no amount of real data can
    /// check — real data never tells you it had nothing in it.
    static let flatline: Person = make(.init(name: "Flatline", seed: 0xF1A7, noiseSD: 0.85,
                   truth: .init(
                       planted: [],
                       forbidden: [.anyVisibleClaim],
                       rationale: "Pure noise. Any visible claim here is a false positive by construction.")))

    /// Meetings genuinely drain this person.
    static let meetingDrain: Person = make(.init(name: "Meeting drain", seed: 0x33E1,
                   truth: .init(
                       planted: [.activityEffect(named: "Meetings", delta: -1.3)],
                       rationale: "A real activity effect, to check the engine attributes it to the activity rather than the hour.")))

    /// A real effect, but only three weeks of it.
    ///
    /// The engine should stay quiet — not because the effect is absent, but
    /// because there is not yet enough to tell. "Not yet" is a legitimate answer
    /// and the current confidence formula has no way to give it.
    static let shortHistory: Person = make(.init(name: "Short history", seed: 0x21D5, days: 18, sessionsPerDay: 1...2,
                   truth: .init(
                       planted: [.timeWindow(better: .morning, worse: .afternoon, delta: 1.1)],
                       forbidden: [.anyVisibleClaim],
                       rationale: "Real effect, too little evidence. Tests whether the engine can say 'not yet'.")))

    /// Heart rate rises in meetings and the person is sitting still.
    static let stillMeetings: Person = make(.init(name: "Still meetings", seed: 0x8B12,
                   truth: .init(
                       planted: [.heartRate(activity: "Meetings", bpm: 11, movement: false)],
                       rationale: "Elevated heart rate with no movement behind it — the case layer 3 should surface.")))

    /// Heart rate rises in meetings because the person walks through them.
    ///
    /// The physiological reading is identical to `stillMeetings`. Only the step
    /// data separates them, which is the entire argument for the movement
    /// residual — and the reason a heart-rate-only engine would be wrong here.
    static let walkingMeetings: Person = make(.init(name: "Walking meetings", seed: 0x8B13,
                   truth: .init(
                       planted: [.heartRate(activity: "Meetings", bpm: 11, movement: true)],
                       forbidden: [.claim(.bodyContext)],
                       rationale: "Same heart rate as Still meetings, explained by walking. Must not read as intensity.")))

    /// Walks at the same pace all day long, meetings included.
    ///
    /// The point of contrast with `walkingMeetings`, whose only brisk windows *are*
    /// their meetings — so the curve there had nothing but meetings to learn
    /// walking from, and "what walking costs" and "what meetings cost" were the
    /// same estimate under two names. This person walks through half of everything
    /// else as well, so the lift at that pace is fitted mostly from windows with no
    /// meeting in them and the meeting residual is a genuine prediction.
    static let walksEverywhere: Person = make(.init(name: "Walks everywhere", seed: 0x8B14,
                   walkingHabit: .init(alwaysDuring: ["Meetings"]),
                   truth: .init(
                       planted: [.movementHabit(cadence: 97, bpm: 11)],
                       forbidden: [.claim(.bodyContext)],
                       rationale: "Walking learned from non-meeting windows, so a near-zero meeting residual is out-of-sample rather than circular.")))

    /// Walks everywhere *and* meetings cost him something on top.
    ///
    /// Case C from the design: movement explains part of the rise and not all of
    /// it. A binary movement gate discards this person, and the near-zero-residual
    /// walker is indistinguishable from him on cadence alone — the residual is the
    /// only thing that has ever been claimed to separate the two.
    static let walksAndStrains: Person = make(.init(name: "Walks and strains", seed: 0x8B15,
                   walkingHabit: .init(alwaysDuring: ["Meetings"]),
                   truth: .init(
                       planted: [.movementHabit(cadence: 97, bpm: 11),
                                 .unexplainedRise(activity: "Meetings", bpm: 9)],
                       rationale: "Movement explains part of the rise. The residual has to recover the remainder, not zero and not all of it.")))

    /// A real drain, but the person stops rating sessions when they go badly.
    ///
    /// The observable ratings are therefore biased upward exactly where the effect
    /// lives. Nothing in the engine notices, and the BRD names this as unsolved —
    /// this person makes the size of the distortion measurable.
    static let skipsTheBadOnes: Person = make(.init(name: "Skips the bad ones", seed: 0x5C1B, skipsLowRatings: true,
                   truth: .init(
                       planted: [.activityEffect(named: "Admin", delta: -1.4)],
                       rationale: "Informative missingness: the drain is real but under-reported, so the measured gap understates it.")))

    /// Everyone, for suites that sweep the cohort.
    static var everyone: [Person] {
        [afternoonSlump, flatline, meetingDrain, shortHistory,
         stillMeetings, walkingMeetings, walksEverywhere, walksAndStrains,
         skipsTheBadOnes]
    }
}
