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
/// correctness: most carry a real effect the engine ought to find, and the rest
/// carry none — or one it should refuse to explain — which is where a pattern
/// engine actually fails.
///
/// The conjunction people at the bottom exist for the same reason twice over. A
/// search over combinations has more ways to be wrong than a search over single
/// factors, and the one that matters is `deepWorkMostlyMorning`: a person whose
/// intersection looks strong because one of its halves is.
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

    // MARK: - Conjunctions

    /// Deep work in the morning, worth more than deep work and mornings combined.
    ///
    /// Both factors carry a little on their own — enough for the main-effect tree
    /// to generate the candidate at all — and the intersection carries far more
    /// than adding them predicts. This is the pattern §6 exists to find, and the
    /// only 2-way in the cohort that should clear the lift gate.
    static let morningDeepWork: Person = make(.init(
        name: "Morning deep work", seed: 0x2A01, baseRating: 2.6, noiseSD: 0.7,
        schedule: .init(activity: "Deep work", prevalence: 0.45, morningShare: 0.5),
        truth: .init(
            planted: [.activityEffect(named: "Deep work", delta: 0.35),
                      .timeWindow(better: .morning, worse: .afternoon, delta: 0.4),
                      .conjunction(activity: "Deep work", bucket: .morning,
                                   afterMedianSleep: false, delta: 1.4)],
            rationale: "A real two-way interaction with small main effects under it. The lift is the whole claim.")))

    /// The same, but only after a night above this person's own sleep median.
    ///
    /// The 2-way is real too and deliberately smaller, so a search that stops at
    /// two factors finds something true and incomplete. The third factor is where
    /// most of the effect lives, and splitting the intersection on sleep is the
    /// only way to see it — which is the argument for the layer existing.
    static let morningDeepWorkAfterSleep: Person = make(.init(
        name: "Morning deep work after sleep", seed: 0x2A02, baseRating: 2.6, noiseSD: 0.7,
        schedule: .init(activity: "Deep work", prevalence: 0.45, morningShare: 0.5),
        truth: .init(
            planted: [.activityEffect(named: "Deep work", delta: 0.3),
                      .conjunction(activity: "Deep work", bucket: .morning,
                                   afterMedianSleep: false, delta: 0.45),
                      .conjunction(activity: "Deep work", bucket: .morning,
                                   afterMedianSleep: true, delta: 1.1)],
            rationale: "A real three-way. The 2-way under it is real and small, so the third factor has to be earned separately.")))

    /// Deep work is good everywhere, and he mostly does it in the morning.
    ///
    /// The critical negative, and the reason the lift gate is in the design at
    /// all. A conjunction search that scores `deep work ∩ morning` against the
    /// rest of his sessions finds a large, real, well-supported difference — and
    /// every bit of it belongs to deep work. Nothing about the morning adds
    /// anything, and the intersection is a weaker claim than the single factor it
    /// is built from, because the deep work he does in the afternoon is just as
    /// good and sits in the baseline dragging it up.
    ///
    /// Seventy percent rather than ninety on purpose. At ninety the intersection
    /// is nearly the whole activity and the two hypotheses stop being separable
    /// even in principle; seventy leaves a real afternoon cell to be wrong about.
    static let deepWorkMostlyMorning: Person = make(.init(
        name: "Deep work, mostly morning", seed: 0x2A03, baseRating: 2.6, noiseSD: 0.7,
        schedule: .init(activity: "Deep work", prevalence: 0.45, morningShare: 0.7),
        truth: .init(
            planted: [.activityEffect(named: "Deep work", delta: 1.5)],
            rationale: "A large main effect and no interaction, in a schedule that makes one look present. The lift gate has to refuse this.")))

    /// Sessions everywhere, ratings from nowhere.
    ///
    /// `flatline` is noise on the default schedule, which puts the first session
    /// of every day in the morning and so leaves most cells too thin to tempt
    /// anybody. This person's sessions are spread across activities and hours,
    /// which fills the conjunction grid with well-populated cells that mean
    /// nothing — the shape a combinatorial search most wants to find something in.
    static let scatteredNoise: Person = make(.init(
        name: "Scattered noise", seed: 0x2A04, baseRating: 3.3, noiseSD: 0.85,
        schedule: .init(activity: "Deep work", prevalence: 0.2,
                        morningShare: Schedule.backgroundMorningShare),
        truth: .init(
            planted: [],
            forbidden: [.anyVisibleClaim],
            rationale: "Noise spread evenly enough to populate every conjunction cell. Any interaction found here is invented.")))

    /// A real conjunction, on five days.
    ///
    /// The effect is large and genuine; there is simply not enough of it. Kept
    /// distinct from `shortHistory`, whose whole record is short — this person has
    /// ninety days of everything else, so the refusal has to come from counting
    /// days *inside the intersection* rather than from the size of the history.
    static let rareMorningCreative: Person = make(.init(
        name: "Rare morning creative", seed: 0x2A05, baseRating: 2.6, noiseSD: 0.7,
        schedule: .init(activity: "Creative", morningShare: 1.0, onlyOnEveryNthDay: 20),
        truth: .init(
            planted: [.conjunction(activity: "Creative", bucket: .morning,
                                   afterMedianSleep: false, delta: 1.5)],
            forbidden: [.anyVisibleClaim],
            rationale: "A real interaction on too few calendar days to support. The day gate, not the lift gate.")))

    /// Everyone, for suites that sweep the cohort.
    static var everyone: [Person] {
        [afternoonSlump, flatline, meetingDrain, shortHistory,
         stillMeetings, walkingMeetings, walksEverywhere, walksAndStrains,
         skipsTheBadOnes,
         morningDeepWork, morningDeepWorkAfterSleep, deepWorkMostlyMorning,
         scatteredNoise, rareMorningCreative]
    }
}
