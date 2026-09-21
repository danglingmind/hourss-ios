import Testing
import Foundation
@testable import Hourss

/// The daily fact: a year of Health history rationed out one fact at a time.
///
/// The properties worth holding are all about restraint rather than about the
/// facts themselves, which `HealthDigestTests` already covers. One a day, never
/// twice, never yesterday's shape again, and nothing at all once the history has
/// been spent — the failure mode this guards against is an app that looks like it
/// has plenty to say by saying the same things again.
@Suite("The daily fact")
@MainActor
struct DailyFactTests {

    // MARK: - Fixtures

    /// A defaults suite per test. `UserDefaults.standard` is shared with every
    /// other suite in the bundle and with whatever the simulator ran last, so a
    /// dispenser written against it would remember facts a previous test spent.
    private func scratchDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "hourss.tests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func day(_ daysAgo: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo,
                              to: Calendar.current.startOfDay(for: Date()))!
    }

    /// A fact with only the fields the dispenser reads set to anything meaningful.
    /// Content is irrelevant here; identity and ordering are the whole subject.
    private func fact(_ metric: HealthMetric, _ kind: HealthDigest.Fact.Kind,
                      strength: Double = 0.2) -> HealthDigest.Fact {
        HealthDigest.Fact(
            figure: "\(metric.rawValue)-\(HealthDigest.kindKey(kind))",
            sentence: "\(metric.rawValue) \(HealthDigest.kindKey(kind))",
            kind: kind, mark: .none,
            strength: strength, subject: .health(metric), raised: true
        )
    }

    /// A year of days, with a value the caller decides per day.
    private func year(_ value: (Date, Bool) -> Double) -> [Date: Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var out: [Date: Double] = [:]
        for offset in 0..<365 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            out[day] = value(day, weekday == 1 || weekday == 7)
        }
        return out
    }

    // MARK: - Rationing

    @Test("One fact per calendar day, however often the screen asks")
    func oneFactPerDay() throws {
        // A view body is re-evaluated for reasons unrelated to the date. Asking
        // five times in one day has to be the same answer five times, or the pool
        // is gone by the afternoon.
        let dispenser = DailyFact(defaults: scratchDefaults())
        let pool = [fact(.steps, .contrast), fact(.sleepHours, .rhythm), fact(.hrv, .drift)]

        let first = try #require(dispenser.fact(for: day(0), from: pool))
        for _ in 0..<4 {
            #expect(dispenser.fact(for: day(0), from: pool)?.sentence == first.sentence)
        }
        #expect(dispenser.spentKeys.count == 1)
    }

    @Test("Nothing is shown twice")
    func factsAreNeverRepeated() {
        let dispenser = DailyFact(defaults: scratchDefaults())
        let pool = [
            fact(.steps, .contrast), fact(.sleepHours, .rhythm), fact(.hrv, .drift),
            fact(.daylightMinutes, .scale), fact(.restingHeartRate, .contrast),
            fact(.activeEnergy, .rhythm),
        ]

        var seen: [String] = []
        for offset in 0..<pool.count {
            guard let fact = dispenser.fact(for: day(pool.count - offset), from: pool) else { continue }
            seen.append(fact.sentence)
        }
        #expect(seen.count == pool.count)
        #expect(Set(seen).count == seen.count, Comment(rawValue: "repeated: \(seen)"))
    }

    @Test("Today is unlike yesterday in both topic and shape")
    func avoidsYesterdaysMetricAndKind() throws {
        let dispenser = DailyFact(defaults: scratchDefaults())
        // Ranked order puts a second steps fact and a second contrast ahead of the
        // only fact that shares neither with the lead, so a dispenser that ignored
        // the previous day would pick one of them.
        let pool = [
            fact(.steps, .contrast, strength: 0.9),
            fact(.steps, .rhythm, strength: 0.8),
            fact(.hrv, .contrast, strength: 0.7),
            fact(.sleepHours, .drift, strength: 0.1),
        ]

        let yesterday = try #require(dispenser.fact(for: day(1), from: pool))
        let today = try #require(dispenser.fact(for: day(0), from: pool))
        #expect(yesterday.subject.key == HealthMetric.steps.rawValue && yesterday.kind == .contrast)
        #expect(today.subject.key != yesterday.subject.key)
        #expect(today.kind != yesterday.kind)
    }

    @Test("Variety is dropped before a day is")
    func fallsBackWhenNothingElseIsLeft() throws {
        // Every remaining fact shares the lead's kind. Refusing them all would
        // mean silence on a day facts still exist for — and, since the rule looks
        // at the last fact *shown*, silence from then on.
        let dispenser = DailyFact(defaults: scratchDefaults())
        let pool = [
            fact(.steps, .contrast, strength: 0.9),
            fact(.hrv, .contrast, strength: 0.5),
        ]

        _ = try #require(dispenser.fact(for: day(1), from: pool))
        let today = try #require(dispenser.fact(for: day(0), from: pool))
        #expect(today.subject.key == HealthMetric.hrv.rawValue)
    }

    @Test("An exhausted pool shows nothing rather than repeating itself")
    func exhaustionReturnsNil() {
        let dispenser = DailyFact(defaults: scratchDefaults())
        let pool = [fact(.steps, .contrast), fact(.sleepHours, .rhythm)]

        #expect(dispenser.fact(for: day(2), from: pool) != nil)
        #expect(dispenser.fact(for: day(1), from: pool) != nil)
        #expect(dispenser.fact(for: day(0), from: pool) == nil)
        // And it stays nil: nothing is recycled on the day after that either.
        #expect(dispenser.fact(for: day(0), from: pool) == nil)
    }

    @Test("An empty pool is not an error")
    func emptyPoolReturnsNil() {
        let dispenser = DailyFact(defaults: scratchDefaults())
        #expect(dispenser.fact(for: day(0), from: []) == nil)
        #expect(dispenser.spentKeys.isEmpty)
    }

    // MARK: - Identity and persistence

    @Test("A fact is identified by what it is, not by its id")
    func identityIsContentNotUUID() {
        let values: [HealthMetric: [Date: Double]] = [
            .sleepHours: year { _, weekend in weekend ? 8.3 : 7.1 },
            .steps: year { _, weekend in weekend ? 10_400 : 8_100 },
        ]
        // `Fact.id` is a fresh UUID per build and the digest is rebuilt on every
        // launch, so identity has to survive a rebuild that changes every id.
        let first = HealthDigest.pool(from: values)
        let second = HealthDigest.pool(from: values)
        #expect(first.map(\.id) != second.map(\.id))
        #expect(first.map(DailyFact.key(for:)) == second.map(DailyFact.key(for:)))
        // Unique within a pool, which is what makes the key usable as a memory of
        // what has been spent.
        let keys = first.map(DailyFact.key(for:))
        #expect(Set(keys).count == keys.count)
    }

    @Test("What has been spent survives a relaunch")
    func spentFactsRoundTrip() throws {
        let defaults = scratchDefaults()
        let pool = [fact(.steps, .contrast), fact(.sleepHours, .rhythm), fact(.hrv, .drift)]

        let yesterday = try #require(DailyFact(defaults: defaults).fact(for: day(1), from: pool))
        // A second dispenser is a relaunch: same defaults, nothing carried in
        // memory.
        let fresh = DailyFact(defaults: defaults)
        #expect(fresh.spentKeys == [DailyFact.key(for: yesterday)])
        #expect(fresh.fact(for: day(1), from: pool)?.sentence == yesterday.sentence)

        let today = try #require(fresh.fact(for: day(0), from: pool))
        #expect(today.sentence != yesterday.sentence)
        #expect(DailyFact(defaults: defaults).spentKeys.count == 2)
    }

    @Test("The same history dispenses the same sequence")
    func dispensingIsDeterministic() {
        let values: [HealthMetric: [Date: Double]] = [
            .sleepHours: year { _, weekend in weekend ? 8.3 : 7.1 },
            .steps: year { _, weekend in weekend ? 10_400 : 8_100 },
            .hrv: year { _, weekend in weekend ? 56 : 49 },
            .daylightMinutes: year { _, weekend in weekend ? 71 : 42 },
        ]

        func sequence() -> [String] {
            let dispenser = DailyFact(defaults: scratchDefaults(UUID().uuidString))
            let pool = HealthDigest.pool(from: values)
            return (0..<5).compactMap { dispenser.fact(for: day(5 - $0), from: pool)?.sentence }
        }
        let first = sequence()
        #expect(!first.isEmpty)
        #expect(sequence() == first)
    }

    @Test("The pool holds everything onboarding threw away")
    func poolIsWiderThanTheDigest() {
        let values: [HealthMetric: [Date: Double]] = [
            .sleepHours: year { _, weekend in weekend ? 8.3 : 7.1 },
            .steps: year { _, weekend in weekend ? 10_400 : 8_100 },
            .hrv: year { _, weekend in weekend ? 56 : 49 },
        ]
        let pool = HealthDigest.pool(from: values)
        let digest = HealthDigest.build(from: values)
        #expect(pool.count > digest.facts.count)
        // And onboarding still leads with what it led with before the pool
        // existed: `build` selects from this same ranking.
        #expect(pool.first?.sentence == digest.facts.first?.sentence)
    }
}
