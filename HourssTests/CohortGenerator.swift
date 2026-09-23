import Foundation
@testable import Hourss

/// Builds a `Person` from a recipe.
///
/// The answer key is the *input*, not a note written alongside it: every rating is
/// produced by applying the `Planted` effects and nothing else, so a person's data
/// and their truth cannot disagree. This mirrors how `Insight.Evidence` works in
/// the app — the claim and its support come from the same array by construction.
extension SyntheticCohort {

    struct Recipe {
        var name: String
        var seed: UInt64
        var days: Int = 90
        var sessionsPerDay: ClosedRange<Int> = 2...4
        /// The person's own centre of gravity. Not a population mean — nothing
        /// here is ever compared across people.
        var baseRating: Double = 3.4
        /// Day-to-day variation with no cause behind it. This is what a claim has
        /// to beat to be worth making.
        var noiseSD: Double = 0.75
        /// Share of eligible sessions that get a feeling score.
        var ratingCoverage: Double = 0.75
        /// When true, draining sessions are *less* likely to be rated — the
        /// informative-missingness case the BRD flags and the engine ignores.
        var skipsLowRatings: Bool = false
        /// Walking the person does as a matter of habit rather than as part of any
        /// one activity. Nil for everybody who does not have one, which keeps the
        /// random stream — and so every existing person — byte-identical.
        var walkingHabit: WalkingHabit? = nil
        /// Explicit placement of sessions across activities and hours. See
        /// `Schedule`. Nil leaves the original day-walking behaviour untouched.
        var schedule: Schedule? = nil
        /// The day this person's history counts back from.
        ///
        /// Stated on the recipe rather than read from the clock inside the
        /// generator, so "when was this person built" cannot be an input to what
        /// they contain. The default is the cohort's fixed anchor; tests that
        /// need to move it — to show that the weekday alignment is the only thing
        /// a date change can reach, and that it reaches a great deal — pass their
        /// own. See `SyntheticCohort.anchor`.
        var anchor: Date = SyntheticCohort.anchor
        var truth: Truth
    }

    /// A person who walks through a good part of their day.
    ///
    /// Modelled per *session* rather than per fifteen-minute window on purpose.
    /// The curve bins a window by its average cadence, so a scatter of
    /// half-walked sessions teaches it about strolling and nothing about walking.
    /// Whole sessions at a pace are what put non-meeting windows in the same
    /// cadence bin the meetings land in, which is the only way the lift fitted
    /// there can be said to have been learned from anything else.
    struct WalkingHabit {
        /// Steps a minute while walking.
        var cadence: ClosedRange<Int> = 85...110
        /// Share of sessions walked through, and of idle stretches too.
        var share: Double = 0.5
        /// What that pace costs them, in beats a minute. One relationship,
        /// applied everywhere the walking happens.
        var bpm: Double = 11
        /// Activities they always walk through, whatever `share` says.
        var alwaysDuring: [String] = []
    }

    /// Where a person's sessions land, rather than where the day happens to put
    /// them.
    ///
    /// A conjunction is as much a claim about *placement* as about ratings. The
    /// default generator walks forward from breakfast, so the first session of
    /// every day is a morning one whatever activity it is, and which activity
    /// lands in which hour is not something a recipe can state. Confounding —
    /// the case the interaction lift gate exists to refuse — cannot be built at
    /// all without saying it: the whole construction is one activity that is
    /// mostly, but not causally, a morning activity.
    ///
    /// Nil for everybody who already existed, which keeps the random stream, and
    /// so every person generated before this, byte-identical.
    struct Schedule {
        /// The activity whose placement is stated rather than drawn.
        var activity: String
        /// Share of sessions that are that activity.
        var prevalence: Double = 0.45
        /// Share of *those* sessions that land in the morning. Equal to
        /// `backgroundMorningShare` is no imbalance at all; 0.7 is the confound.
        var morningShare: Double = 0.5
        /// Confines the activity to every nth day, so a real conjunction can exist
        /// on too few calendar days to be worth supporting.
        var onlyOnEveryNthDay: Int? = nil
        /// What everything else keeps. Held fixed so the hour is a proxy for the
        /// activity only to the extent `morningShare` makes it one, and a person
        /// with no imbalance genuinely has none rather than a smaller one.
        static let backgroundMorningShare = 0.35
    }

    static func make(_ recipe: Recipe) -> Person {
        var rng = Seeded(seed: recipe.seed)
        let calendar = Calendar.current
        let activities = Activity.defaults
        // Read once. Every day in this person — sleep, sessions, samples — is an
        // offset from this one value, so there is no arrangement of the loops
        // below in which two of them can disagree about what day it is.
        let anchor = recipe.anchor

        // ── Health first: ratings may depend on the previous night's sleep ──
        var sleepByDay: [Date: Double] = [:]
        for offset in 0...recipe.days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: anchor) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            sleepByDay[day] = (isWeekend ? 8.1 : 7.1) + gaussian(&rng, sd: 0.55)
        }
        let sleepMean = sleepByDay.values.reduce(0, +) / Double(sleepByDay.count)
        /// The median rather than the mean, because that is the predicate §6.4
        /// writes into a three-way hypothesis — "health.sleep >= median". A
        /// conjunction planted against one boundary and read against another
        /// would land half its sessions on the wrong side of its own answer key.
        let sleepMedian = sleepByDay.values.sorted()[sleepByDay.count / 2]

        var sessions: [Session] = []
        var reflections: [UUID: Reflection] = [:]
        /// Windows the heart-rate generator needs, so physiology lines up with the
        /// sessions rather than being invented independently.
        var occupied: [(range: ClosedRange<Date>, activity: String)] = []

        for offset in 0..<recipe.days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: anchor) else { continue }
            let sleepLastNight = sleepByDay[day] ?? sleepMean

            var hour = Int.random(in: 8...10, using: &rng)
            let count = Int.random(in: recipe.sessionsPerDay, using: &rng)

            // Drawn up front for scheduled people, because slots are handed out
            // without replacement and that is a decision about the whole day.
            var plan: [PlannedSession] = []
            if let schedule = recipe.schedule {
                plan = plannedDay(schedule, dayOffset: offset, count: count,
                                  activities: activities, rng: &rng)
            }

            for index in 0..<count {
                let activity: Activity
                let minutes: Int
                let start: Date
                if recipe.schedule != nil {
                    guard index < plan.count else { break }
                    let slot = plan[index]
                    activity = slot.activity
                    minutes = slot.minutes
                    guard let at = calendar.date(bySettingHour: slot.hour, minute: slot.minute,
                                                 second: 0, of: day) else { break }
                    start = at
                } else {
                    guard hour < 21 else { break }
                    activity = activities[Int.random(in: 0..<activities.count, using: &rng)]
                    minutes = [25, 45, 50, 60, 75, 95, 120][Int.random(in: 0...6, using: &rng)]

                    guard let at = calendar.date(bySettingHour: hour,
                                                 minute: Int.random(in: 0...45, using: &rng),
                                                 second: 0, of: day) else { break }
                    start = at
                }
                let end = start.addingTimeInterval(TimeInterval(minutes * 60))
                let session = Session(activityId: activity.id, startAt: start, endAt: end)
                sessions.append(session)
                occupied.append((start...end, activity.name))

                // ── The rating: base + every planted effect + noise, nothing else
                var value = recipe.baseRating
                for effect in recipe.truth.planted {
                    value += contribution(of: effect,
                                          to: session,
                                          named: activity.name,
                                          sleepLastNight: sleepLastNight,
                                          sleepMean: sleepMean,
                                          sleepMedian: sleepMedian)
                }
                value += gaussian(&rng, sd: recipe.noiseSD)
                let rating = max(1, min(5, Int(value.rounded())))

                // ── Whether they bothered to rate it
                var coverage = recipe.ratingCoverage
                if recipe.skipsLowRatings && rating <= 2 { coverage *= 0.3 }
                if Double.random(in: 0...1, using: &rng) < coverage {
                    reflections[session.id] = Reflection(
                        sessionId: session.id,
                        feelingScore: rating,
                        performanceScore: max(1, min(5, rating + Int.random(in: -1...1, using: &rng))),
                        note: nil,
                        submittedAt: end
                    )
                }
                if recipe.schedule == nil {
                    hour += max(1, minutes / 60) + Int.random(in: 1...2, using: &rng)
                }
            }
        }

        let health = healthSamples(recipe: recipe,
                                   anchor: anchor,
                                   sleepByDay: sleepByDay,
                                   occupied: occupied,
                                   rng: &rng)

        return Person(recipe: recipe,
                      activities: activities,
                      sessions: sessions,
                      reflections: reflections,
                      samples: health.byMetric,
                      heartRate: health.heartRate)
    }

    struct PlannedSession {
        let activity: Activity
        let hour: Int
        let minute: Int
        let minutes: Int
    }

    /// Lays out one day's sessions at stated hours.
    ///
    /// Slots are handed out without replacement and every session is short enough
    /// to finish inside its own hour, so a day never has two sessions claiming the
    /// same minutes — the heart-rate generator reads these windows and overlapping
    /// ones would make an activity's physiology partly somebody else's.
    private static func plannedDay(
        _ schedule: Schedule,
        dayOffset: Int,
        count: Int,
        activities: [Activity],
        rng: inout Seeded
    ) -> [PlannedSession] {
        let target = activities.first { $0.name == schedule.activity }
        let others = activities.filter { $0.name != schedule.activity }
        guard !others.isEmpty else { return [] }

        // Morning is 05–11; the remaining pool spans midday, afternoon and
        // evening so "not morning" is a mixture rather than a second single hour.
        var morning = [7, 8, 9, 10]
        var later = [11, 12, 14, 15, 16, 18, 19]

        var out: [PlannedSession] = []
        for index in 0..<count {
            var isTarget = Double.random(in: 0...1, using: &rng) < schedule.prevalence
            if let stride = schedule.onlyOnEveryNthDay {
                // One occurrence, on its own days, and none anywhere else — a real
                // conjunction spread over a countable number of calendar days.
                isTarget = dayOffset % stride == 0 && index == 0
            }

            let wantsMorning = Double.random(in: 0...1, using: &rng)
                < (isTarget ? schedule.morningShare : Schedule.backgroundMorningShare)
            var pool = wantsMorning ? morning : later
            if pool.isEmpty { pool = wantsMorning ? later : morning }
            guard !pool.isEmpty else { break }

            let hour = pool[Int.random(in: 0..<pool.count, using: &rng)]
            morning.removeAll { $0 == hour }
            later.removeAll { $0 == hour }

            let activity: Activity
            if isTarget, let target {
                activity = target
            } else {
                activity = others[Int.random(in: 0..<others.count, using: &rng)]
            }

            out.append(PlannedSession(activity: activity,
                                      hour: hour,
                                      minute: Int.random(in: 0...5, using: &rng),
                                      minutes: [25, 45, 50][Int.random(in: 0...2, using: &rng)]))
        }
        return out.sorted { $0.hour < $1.hour }
    }

    /// How much one planted effect moves one session's rating. Effects that do not
    /// apply to this session contribute exactly zero.
    private static func contribution(
        of effect: Planted,
        to session: Session,
        named: String,
        sleepLastNight: Double,
        sleepMean: Double,
        sleepMedian: Double
    ) -> Double {
        switch effect {
        case let .timeWindow(_, worse, delta):
            session.timeBucket == worse ? -delta : 0
        case let .activityEffect(name, delta):
            named == name ? delta : 0
        case let .durationEffect(bucket, delta):
            session.durationBucket == bucket ? delta : 0
        case let .sleepAssociation(delta):
            (sleepLastNight - sleepMean) * delta
        case let .conjunction(activity, bucket, afterMedianSleep, delta):
            // Every condition, or nothing. A session that satisfies two of three
            // gets exactly zero of this effect — which is what makes the lift the
            // planted number rather than something smeared across the margins.
            (named == activity
             && session.timeBucket == bucket
             && (!afterMedianSleep || sleepLastNight >= sleepMedian)) ? delta : 0
        case .heartRate, .movementHabit, .unexplainedRise:
            0   // physiological, not a rating effect
        }
    }
}
