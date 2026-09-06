import Foundation
@testable import Hourss

/// Health generation at the resolution HealthKit actually stores.
///
/// Samples carry real timestamps and are laid down *around the generated
/// sessions*, so a heart-rate effect and the session it belongs to refer to the
/// same forty minutes. The daily rollup on `Person` then reproduces what our
/// current `intervalComponents: DateComponents(day: 1)` query would return — which
/// makes the resolution we throw away measurable rather than argued about.
extension SyntheticCohort {

    /// Sampling interval for the dense types. Real wrist heart rate is irregular;
    /// a fixed grid is close enough for testing attribution and much easier to
    /// reason about when a test fails.
    private static let samplingMinutes = 15

    static func healthSamples(
        recipe: Recipe,
        sleepByDay: [Date: Double],
        occupied: [(range: ClosedRange<Date>, activity: String)],
        rng: inout Seeded
    ) -> (byMetric: [HealthMetric: [Sample]], heartRate: [Sample]) {
        let calendar = Calendar.current
        var out: [HealthMetric: [Sample]] = [:]

        // ── Sleep: one value per night, which is genuinely all there is ──
        out[.sleepHours] = sleepByDay
            .map { Sample(at: $0.key, value: $0.value) }
            .sorted { $0.at < $1.at }

        // ── Resting heart rate: Apple derives one per day. Not our aggregation.
        var restingSamples: [Sample] = []
        // ── HRV: a handful a day, mostly overnight. Too sparse to attribute to
        //    any single waking hour however it is queried.
        var hrvSamples: [Sample] = []
        var heartRate: [Sample] = []
        var steps: [Sample] = []

        let hrEffects: [(activity: String, bpm: Double, movement: Bool)] =
            recipe.truth.planted.compactMap {
                if case let .heartRate(activity, bpm, movement) = $0 {
                    return (activity, bpm, movement)
                }
                return nil
            }

        // The part of an activity's rise that movement does not buy, for people
        // who walk through everything and whose meetings still cost them
        // something extra on top. Kept apart from `.heartRate` because for those
        // people "the rise" and "the rise movement cannot explain" are different
        // numbers, and only the second is what the residual claims to recover.
        let unexplained: [(activity: String, bpm: Double)] =
            recipe.truth.planted.compactMap {
                if case let .unexplainedRise(activity, bpm) = $0 { return (activity, bpm) }
                return nil
            }

        // Which sessions a habitual walker walks through, drawn once per session
        // rather than per window. See `WalkingHabit` for why the decision has to
        // be at session granularity to teach the curve anything.
        let habit = recipe.walkingHabit
        var walkedSessions: Set<Int> = []
        if let habit {
            for (index, window) in occupied.enumerated() {
                // Drawn unconditionally so the stream depends on the session
                // count alone, not on which activity happened to come up.
                let drawn = Double.random(in: 0...1, using: &rng) < habit.share
                if habit.alwaysDuring.contains(window.activity) || drawn {
                    walkedSessions.insert(index)
                }
            }
        }

        for offset in 0..<recipe.days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: anchor) else { continue }
            let sleep = sleepByDay[day] ?? 7.2

            restingSamples.append(Sample(at: day.addingTimeInterval(6 * 3600),
                                         value: 60 - (sleep - 7.2) * 1.4 + gaussian(&rng, sd: 1.6)))
            for hrvHour in [3, 5] {
                hrvSamples.append(Sample(at: day.addingTimeInterval(Double(hrvHour) * 3600),
                                         value: 48 + (sleep - 7.2) * 5 + gaussian(&rng, sd: 5)))
            }

            for minuteOfDay in stride(from: 7 * 60, to: 23 * 60, by: samplingMinutes) {
                let at = day.addingTimeInterval(Double(minuteOfDay) * 60)
                let hour = Double(minuteOfDay) / 60

                // Circadian baseline: lowest early, peaking mid-afternoon.
                var bpm = 62 + 7 * sin((hour - 7) / 16 * .pi)
                var stepsInWindow = Double(Int.random(in: 0...40, using: &rng))

                if let match = occupied.first(where: { $0.range.contains(at) }),
                   let effect = hrEffects.first(where: { $0.activity == match.activity }) {
                    bpm += effect.bpm
                    if effect.movement {
                        // Walking through the session: roughly 100 steps a minute.
                        stepsInWindow += Double(samplingMinutes) * Double(Int.random(in: 85...110, using: &rng))
                    }
                }

                // ── A walking habit: the same pace at the same cost wherever it
                //    happens, sessions and idle stretches alike. Nothing in here
                //    knows what a meeting is, and that is the entire point. The
                //    curve can then learn what walking costs from windows that
                //    have no meeting in them, which turns the meeting residual
                //    from a fit to itself into a prediction.
                if let habit {
                    let inSession = occupied.firstIndex { $0.range.contains(at) }
                    // Both drawn every window so the stream does not depend on
                    // where the sessions happened to fall.
                    let idleWalk = Double.random(in: 0...1, using: &rng) < habit.share
                    let pace = Double(Int.random(in: habit.cadence, using: &rng))
                    if inSession.map(walkedSessions.contains) ?? idleWalk {
                        stepsInWindow += Double(samplingMinutes) * pace
                        bpm += habit.bpm
                    }
                }

                // A rise on top of whatever movement explains — case C, the one
                // a binary movement gate would throw away entirely.
                if let match = occupied.first(where: { $0.range.contains(at) }),
                   let extra = unexplained.first(where: { $0.activity == match.activity }) {
                    bpm += extra.bpm
                }

                // Ambient walking bouts unrelated to anything logged.
                if Int.random(in: 0...11, using: &rng) == 0 {
                    let bout = Double(Int.random(in: 300...900, using: &rng))
                    stepsInWindow += bout
                    bpm += bout / 90    // the confounder the residual has to remove
                }

                heartRate.append(Sample(at: at, value: bpm + gaussian(&rng, sd: 2.5)))
                steps.append(Sample(at: at, value: max(0, stepsInWindow)))
            }
        }

        out[.restingHeartRate] = restingSamples
        out[.hrv] = hrvSamples
        out[.steps] = steps

        // Heart rate is returned separately, not under a `HealthMetric`: there is
        // no case for it because the app does not read it.
        return (out, heartRate)
    }

    /// Heart-rate samples inside one session's window.
    static func heartRate(during session: Session, from samples: [Sample]) -> [Sample] {
        guard let end = session.endAt else { return [] }
        return samples.filter { $0.at >= session.startAt && $0.at <= end }
    }

    /// Steps per minute across a session — the pace figure the residual needs,
    /// which a step *total* cannot give you.
    static func cadence(during session: Session, steps: [Sample]) -> Double {
        guard let end = session.endAt else { return 0 }
        let inside = steps.filter { $0.at >= session.startAt && $0.at <= end }
        guard !inside.isEmpty else { return 0 }
        let minutes = end.timeIntervalSince(session.startAt) / 60
        return inside.reduce(0) { $0 + $1.value } / max(minutes, 1)
    }
}
