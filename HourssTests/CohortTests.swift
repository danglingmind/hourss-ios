import Testing
import Foundation
@testable import Hourss

/// The cohort has to be trustworthy before it can judge anything.
///
/// These check the generator itself: that a planted effect is genuinely present in
/// the ratings, that an absent one genuinely is not, and that two runs produce the
/// same people. A test suite built on a generator nobody verified would just move
/// the unverified step one level down.
@Suite("Synthetic cohort")
struct CohortTests {

    /// Rated sessions matching a predicate, paired with their day.
    private func rated(_ person: SyntheticCohort.Person,
                       where predicate: (Session, String) -> Bool) -> [(day: Date, score: Int)] {
        let names = Dictionary(uniqueKeysWithValues: person.activities.map { ($0.id, $0.name) })
        let calendar = Calendar.current
        return person.sessions.compactMap { session in
            guard let score = person.reflections[session.id]?.feelingScore,
                  predicate(session, names[session.activityId] ?? "") else { return nil }
            return (calendar.startOfDay(for: session.startAt), score)
        }
    }

    /// Distinct calendar days behind a group. The gate in §6.2 counts these, not
    /// sessions, so a fixture meant to fail it has to be thin in the right unit.
    private func days(_ person: SyntheticCohort.Person,
                      where predicate: (Session, String) -> Bool) -> Int {
        Set(rated(person, where: predicate).map(\.day)).count
    }

    /// What the two main effects alone predict for their intersection.
    ///
    /// Estimated from the person's own four cells rather than from the recipe, so
    /// the test measures the data rather than restating the input. In an additive
    /// world the intersection is the two margins minus the baseline they share;
    /// whatever the cell does above that is interaction and nothing else.
    private func additive(_ person: SyntheticCohort.Person,
                          activity: String,
                          bucket: TimeBucket) -> (observed: Double, predicted: Double)? {
        guard let both = mean(person, where: { s, n in n == activity && s.timeBucket == bucket }),
              let activityOnly = mean(person, where: { s, n in n == activity && s.timeBucket != bucket }),
              let bucketOnly = mean(person, where: { s, n in n != activity && s.timeBucket == bucket }),
              let neither = mean(person, where: { s, n in n != activity && s.timeBucket != bucket })
        else { return nil }
        return (both, activityOnly + bucketOnly - neither)
    }

    /// Mean feeling score across sessions matching a predicate.
    private func mean(_ person: SyntheticCohort.Person,
                      where predicate: (Session, String) -> Bool) -> Double? {
        let names = Dictionary(uniqueKeysWithValues: person.activities.map { ($0.id, $0.name) })
        let scores = person.sessions.compactMap { session -> Int? in
            guard let score = person.reflections[session.id]?.feelingScore,
                  predicate(session, names[session.activityId] ?? "") else { return nil }
            return score
        }
        guard !scores.isEmpty else { return nil }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }

    @Test("Generation is deterministic")
    func deterministic() {
        let a = SyntheticCohort.afternoonSlump
        let b = SyntheticCohort.afternoonSlump
        #expect(a.sessions.count == b.sessions.count)
        #expect(a.sessions.map(\.startAt) == b.sessions.map(\.startAt))
        #expect(a.reflections.count == b.reflections.count)
    }

    @Test("A planted time-of-day effect is really in the ratings")
    func afternoonSlumpIsReal() throws {
        let person = SyntheticCohort.afternoonSlump
        let morning = try #require(mean(person) { s, _ in s.timeBucket == .morning })
        let afternoon = try #require(mean(person) { s, _ in s.timeBucket == .afternoon })
        // Planted at 1.2; rounding to integers and clamping to 1...5 shrinks it.
        #expect(morning - afternoon > 0.5,
                "planted afternoon slump did not survive generation: \(morning) vs \(afternoon)")
    }

    @Test("A planted activity effect is really in the ratings")
    func meetingDrainIsReal() throws {
        let person = SyntheticCohort.meetingDrain
        let meetings = try #require(mean(person) { _, name in name == "Meetings" })
        let rest = try #require(mean(person) { _, name in name != "Meetings" })
        #expect(rest - meetings > 0.5,
                "planted meeting drain did not survive generation: \(rest) vs \(meetings)")
    }

    @Test("The flatline person really has no time-of-day effect")
    func flatlineIsFlat() throws {
        let person = SyntheticCohort.flatline
        let byBucket = try TimeBucket.allCases.compactMap { bucket -> Double? in
            mean(person) { s, _ in s.timeBucket == bucket }
        }
        let spread = try #require(byBucket.max()) - (try #require(byBucket.min()))
        #expect(spread < 0.45,
                "flatline person has a \(spread) spread across time buckets — not flat enough to test against")
    }

    @Test("Informative missingness biases the observable ratings upward")
    func missingnessBiasesUpward() throws {
        let person = SyntheticCohort.skipsTheBadOnes
        let names = Dictionary(uniqueKeysWithValues: person.activities.map { ($0.id, $0.name) })
        let admin = person.sessions.filter { names[$0.activityId] == "Admin" }
        let rated = admin.compactMap { person.reflections[$0.id]?.feelingScore }
        let coverage = Double(rated.count) / Double(admin.count)
        // Everyone else sits near the recipe's 0.75 coverage.
        #expect(coverage < 0.72,
                "expected under-reporting on the draining activity, got \(coverage) coverage")
    }

    @Test("Health samples keep sub-daily resolution")
    func samplesAreSubDaily() throws {
        let person = SyntheticCohort.stillMeetings
        let steps = try #require(person.samples[.steps])
        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: try #require(steps.first).at)
        let sameDay = steps.filter { calendar.startOfDay(for: $0.at) == firstDay }
        #expect(sameDay.count > 20,
                "steps collapsed to \(sameDay.count) samples a day — the resolution layer 3 needs is gone")

        // And the rollup reproduces exactly what today's daily query would give.
        let rolled = person.healthByDay[.steps] ?? [:]
        #expect(rolled[firstDay] != nil)
        #expect(rolled.count <= steps.count / 20)
    }

    @Test("Walking and still meetings are physiologically identical, and only steps separate them")
    func movementIsTheOnlyDifference() throws {
        let still = SyntheticCohort.stillMeetings
        let walking = SyntheticCohort.walkingMeetings

        func meetingHR(_ p: SyntheticCohort.Person) -> Double {
            let names = Dictionary(uniqueKeysWithValues: p.activities.map { ($0.id, $0.name) })
            let windows = p.sessions.filter { names[$0.activityId] == "Meetings" }
            let bpm = windows.flatMap { SyntheticCohort.heartRate(during: $0, from: p.heartRate) }
            return bpm.reduce(0) { $0 + $1.value } / Double(max(bpm.count, 1))
        }
        func meetingCadence(_ p: SyntheticCohort.Person) -> Double {
            let names = Dictionary(uniqueKeysWithValues: p.activities.map { ($0.id, $0.name) })
            let windows = p.sessions.filter { names[$0.activityId] == "Meetings" }
            let steps = p.samples[.steps] ?? []
            let values = windows.map { SyntheticCohort.cadence(during: $0, steps: steps) }
            return values.reduce(0, +) / Double(max(values.count, 1))
        }

        // Heart rate alone cannot tell these two people apart...
        #expect(abs(meetingHR(still) - meetingHR(walking)) < 6,
                "the two meeting people should look similar on heart rate alone")
        // ...but cadence separates them decisively.
        #expect(meetingCadence(walking) > meetingCadence(still) * 4,
                "walking meetings should show far higher cadence: \(meetingCadence(walking)) vs \(meetingCadence(still))")
    }

    // MARK: - Conjunctions

    @Test("The planted two-way interaction beats what its main effects predict")
    func twoWayInteractionIsReal() throws {
        let person = SyntheticCohort.morningDeepWork
        let cell = try #require(additive(person, activity: "Deep work", bucket: .morning))
        let lift = cell.observed - cell.predicted
        // Planted at 1.4; integer rounding and the ceiling at 5 shrink it.
        #expect(lift > 0.6, Comment(rawValue:
                "planted 2-way did not survive generation: cell \(cell.observed) vs additive \(cell.predicted)"))
        #expect(days(person) { s, n in n == "Deep work" && s.timeBucket == .morning } >= 6,
                "the intersection needs enough distinct days to be testable at all")
    }

    @Test("The planted three-way needs its sleep condition to appear")
    func threeWayInteractionIsReal() throws {
        let person = SyntheticCohort.morningDeepWorkAfterSleep
        let sleep = try #require(person.healthByDay[.sleepHours])
        let median = sleep.values.sorted()[sleep.count / 2]
        let calendar = Calendar.current

        func cell(afterMedianSleep: Bool) -> Double? {
            mean(person) { s, n in
                guard n == "Deep work", s.timeBucket == .morning,
                      let hours = sleep[calendar.startOfDay(for: s.startAt)] else { return false }
                return (hours >= median) == afterMedianSleep
            }
        }
        let rested = try #require(cell(afterMedianSleep: true))
        let tired = try #require(cell(afterMedianSleep: false))
        // Planted at 1.1 on top of a 0.45 two-way that both halves share.
        #expect(rested - tired > 0.5, Comment(rawValue:
                "the third factor bought nothing: \(rested) rested vs \(tired) tired"))

        // The two-way underneath is real too, so a search that stops at two
        // factors finds something true — and materially incomplete.
        let two = try #require(additive(person, activity: "Deep work", bucket: .morning))
        let twoWayLift = two.observed - two.predicted
        #expect(twoWayLift > 0.3, Comment(rawValue: "the 2-way under the 3-way vanished: \(twoWayLift)"))

        // What §6.2 actually asks of a three-way: a lift over the strongest
        // two-way it is built from. Measured against that cell rather than
        // against `tired`, because the pooled two-way already contains half of
        // the sleep effect and comparing to it would score the same quantity
        // twice — the mistake this fixture exists to keep somebody from making
        // in the engine.
        #expect(rested - two.observed > 0.3, Comment(rawValue:
                "conditioning on sleep bought only \(rested - two.observed) over the 2-way cell at \(two.observed)"))
    }

    /// The number the interaction lift gate will be judged against.
    ///
    /// This person's `deep work ∩ morning` cell really is far above his other
    /// sessions — a naive search scores it well and it is entirely an artifact of
    /// when he happens to do deep work. The gate compares the intersection against
    /// its strongest constituent factor rather than against the baseline, and this
    /// is the person who makes the difference between those two comparisons
    /// visible.
    @Test("The confounded person's conjunction is nothing but its main effect")
    func confoundIsMainEffectOnly() throws {
        let person = SyntheticCohort.deepWorkMostlyMorning

        let cell = try #require(mean(person) { s, n in n == "Deep work" && s.timeBucket == .morning })
        let outside = try #require(mean(person) { s, n in !(n == "Deep work" && s.timeBucket == .morning) })
        let deep = try #require(mean(person) { _, n in n == "Deep work" })
        let rest = try #require(mean(person) { _, n in n != "Deep work" })

        // The confound has to be there for the person to be worth anything.
        let morningShare = Double(rated(person) { s, n in n == "Deep work" && s.timeBucket == .morning }.count)
            / Double(rated(person) { _, n in n == "Deep work" }.count)
        #expect(morningShare > 0.6, Comment(rawValue:
                "only \(morningShare) of deep work is in the morning — not enough imbalance to fool anything"))

        // What a naive search sees, and what the single factor already explains.
        let apparent = cell - outside
        let mainEffect = deep - rest
        #expect(apparent > 0.8, Comment(rawValue:
                "the trap has to be tempting: apparent conjunction effect is only \(apparent)"))
        // The gate's own quantity. Below zero, not merely below its threshold:
        // the deep work he does outside the morning is just as good and sits in
        // the baseline, so the intersection is a *weaker* claim than the single
        // factor it was built from.
        #expect(apparent - mainEffect < -0.15, Comment(rawValue:
                "interaction lift is \(apparent - mainEffect) (\(apparent) over baseline, \(mainEffect) from the activity alone) — not far enough below the gate to test it"))

        // And on the gate's own arithmetic there is nothing left over.
        let additiveCell = try #require(additive(person, activity: "Deep work", bucket: .morning))
        let lift = additiveCell.observed - additiveCell.predicted
        #expect(abs(lift) < 0.2, Comment(rawValue: "residual interaction of \(lift) where none was planted"))
    }

    @Test("No conjunction stands out for the person who has none")
    func noInteractionIsInvented() throws {
        let person = SyntheticCohort.scatteredNoise
        var worst = (lift: -Double.infinity, label: "")
        for activity in person.activities.map(\.name) {
            for bucket in TimeBucket.allCases {
                // Only cells a search would be allowed to reach. An unfiltered
                // maximum over every thin corner of the grid measures the day gate
                // rather than this person.
                guard days(person, where: { s, n in n == activity && s.timeBucket == bucket }) >= 6,
                      let cell = additive(person, activity: activity, bucket: bucket) else { continue }
                let lift = cell.observed - cell.predicted
                if lift > worst.lift { worst = (lift, "\(activity) ∩ \(bucket.label)") }
            }
        }
        #expect(worst.lift < 0.6, Comment(rawValue:
                "\(worst.label) shows a \(worst.lift) interaction lift in pure noise — too large for the gate to be tested against"))
    }

    @Test("The thin conjunction is real and lands on too few days to support")
    func thinConjunctionIsThin() throws {
        let person = SyntheticCohort.rareMorningCreative
        let cellDays = days(person) { s, n in n == "Creative" && s.timeBucket == .morning }
        #expect(cellDays < 6, Comment(rawValue:
                "the rare conjunction covers \(cellDays) days — the day gate would let it through"))
        // Still ninety days of history behind it, so the refusal has to come from
        // counting days inside the intersection rather than from a short record.
        #expect(days(person) { _, _ in true } > 60,
                "this person's refusal must not be reducible to a short history")
    }

    /// Two separate concerns wearing one name.
    ///
    /// The generator has to be reproducible, or a failing fixture cannot be
    /// investigated. And the people have to be *cached*, because `Session.init`
    /// mints a fresh UUID — a computed person hands out different identifiers on
    /// every access, so `reflections[session.id]` from one access misses every
    /// session from another and the ratings silently vanish rather than mismatch.
    @Test("Conjunction people are reproducible, and stable across accesses")
    func conjunctionPeopleAreDeterministic() {
        let recipe = SyntheticCohort.Recipe(
            name: "Repeat", seed: 0x2A03, baseRating: 2.6, noiseSD: 0.7,
            schedule: .init(activity: "Deep work", prevalence: 0.45, morningShare: 0.7),
            truth: .init(planted: [.activityEffect(named: "Deep work", delta: 1.5)]))
        let first = SyntheticCohort.make(recipe)
        let second = SyntheticCohort.make(recipe)
        #expect(first.sessions.map(\.startAt) == second.sessions.map(\.startAt),
                "two runs of one recipe placed sessions differently")
        #expect(first.sessions.map(\.activityId) == second.sessions.map(\.activityId),
                "two runs of one recipe chose different activities")
        #expect(first.sessions.compactMap { first.reflections[$0.id]?.feelingScore }
                == second.sessions.compactMap { second.reflections[$0.id]?.feelingScore },
                "two runs of one recipe produced different ratings")

        for person in [SyntheticCohort.morningDeepWork,
                       SyntheticCohort.morningDeepWorkAfterSleep,
                       SyntheticCohort.deepWorkMostlyMorning,
                       SyntheticCohort.scatteredNoise,
                       SyntheticCohort.rareMorningCreative] {
            let again = SyntheticCohort.everyone.first { $0.name == person.name }
            #expect(again?.sessions.map(\.id) == person.sessions.map(\.id), Comment(rawValue:
                    "\(person.name) handed out different session ids on a second access"))
            // Non-empty, or two accesses that both lost every rating would agree.
            #expect(person.ratedCount > 100, Comment(rawValue:
                    "\(person.name) has \(person.ratedCount) rated sessions — too few to compare against anything"))
        }
    }

    // MARK: - The time basis

    /// Everything about a person except the dates they are written on.
    ///
    /// Day *offsets* from the person's own anchor rather than absolute days, so
    /// two people built against two different anchors are comparable — which is
    /// the whole question below. Sleep is in here because it is the channel: the
    /// generator pays a weekend bonus, so a person's sleep series is the one thing
    /// that changes when the anchor moves by anything other than whole weeks.
    private func fingerprint(_ person: SyntheticCohort.Person) -> [String] {
        let calendar = Calendar.current
        let anchor = person.recipe.anchor
        func offset(_ date: Date) -> Int {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                    to: anchor).day ?? .min
        }

        var out: [String] = person.sessions.map { session in
            let parts = calendar.dateComponents([.hour, .minute], from: session.startAt)
            let minutes = (session.endAt?.timeIntervalSince(session.startAt) ?? 0) / 60
            let rating = person.reflections[session.id]?.feelingScore
            return "s \(offset(session.startAt)) \(parts.hour ?? -1):\(parts.minute ?? -1)"
                + " \(Int(minutes)) \(session.activityId) \(rating.map(String.init) ?? "—")"
        }
        for (day, hours) in (person.healthByDay[.sleepHours] ?? [:]).sorted(by: { $0.key < $1.key }) {
            out.append(String(format: "sleep %d %.6f", offset(day), hours))
        }
        return out
    }

    /// The cohort must be the same cohort whatever moment it is built at.
    ///
    /// It was not. `anchor` was `startOfDay(for: Date())`, so the whole history
    /// rotated with the calendar: every session's weekday moved, and with it
    /// `isWorkday` on every observation and the weekend bonus in the sleep the
    /// search conditions on. Rebuilt against each of the seven alignments in turn,
    /// the planted three-way is admitted by the recommended procedure on five of
    /// them and refused on two — so `InteractionCorrectionTests.cohortMeasurement`
    /// failed on about two days a week and passed on the rest, with nothing in the
    /// diff to explain either. `SyntheticCohort.anchor` carries the measurement.
    ///
    /// The anchor is now the most recent Monday, which is not a constant and does
    /// not need to be. Every value it can take differs from every other by a whole
    /// number of weeks, and the claim that makes that a fix rather than a
    /// rearrangement is the third one below: generation is invariant under
    /// whole-week shifts. Asserted, not described — fifty-two weeks away is as
    /// different a wall clock as this can be handed, and the people have to come
    /// back line for line.
    ///
    /// Four claims:
    /// 1. the basis is a Monday, resolved once, and every person shares it;
    /// 2. nothing generated is written outside the days behind it, which is what a
    ///    `Date()` reintroduced anywhere inside generation would break;
    /// 3. a whole-week shift changes nothing at all;
    /// 4. a one-day shift changes everybody — so the pinning is load-bearing
    ///    rather than tidy, and a generator that stopped reading the weekday would
    ///    be caught here rather than trusted.
    @Test("The cohort's time basis is fixed, and moving it off a week boundary would change every person")
    func timeBasisIsFixed() throws {
        let calendar = Calendar.current
        let anchor = SyntheticCohort.anchor

        // ── 1. A Monday, at a start of day, within the last week.
        let parts = calendar.dateComponents([.weekday, .hour, .minute, .second], from: anchor)
        #expect(parts.weekday == 2, Comment(rawValue:
                "the anchor is not a Monday but \(anchor) — whole-week invariance is the only thing making a moving anchor safe"))
        #expect(parts.hour == 0 && parts.minute == 0 && parts.second == 0,
                "the anchor must be a start of day, or two people built minutes apart are built against different instants")
        let today = calendar.startOfDay(for: Date())
        let weekAgo = try #require(calendar.date(byAdding: .day, value: -7, to: today))
        #expect(anchor <= today && anchor > weekAgo, Comment(rawValue:
                "the anchor is \(anchor), outside the last week — the cohort has to stay inside HealthService.physiologyDays"))
        // The rule itself, at days this run did not land on: seven consecutive
        // dates must map to one Monday, or "resolved once" is doing the work
        // rather than the rule.
        let mondays = Set((0...6).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: anchor)
                .map { SyntheticCohort.mostRecentMonday(onOrBefore: $0) }
        })
        #expect(mondays == [anchor], Comment(rawValue:
                "a week of dates resolved to \(mondays.count) different anchors"))

        // ── 2. One basis for the whole cohort, and nothing written outside it.
        let ceiling = try #require(calendar.date(byAdding: .day, value: 1, to: anchor))
        for person in SyntheticCohort.everyone {
            #expect(person.recipe.anchor == anchor, Comment(rawValue:
                    "\(person.name) was built against a different time basis from the rest of the cohort"))
            let floor = try #require(calendar.date(byAdding: .day, value: -(person.recipe.days + 2), to: anchor))
            var stamps = person.sessions.flatMap { [$0.startAt, $0.endAt ?? $0.startAt] }
            stamps += person.reflections.values.map(\.submittedAt)
            stamps += person.samples.values.flatMap { $0.map(\.at) }
            stamps += person.heartRate.map(\.at)
            let latest = try #require(stamps.max())
            let earliest = try #require(stamps.min())
            #expect(latest <= ceiling && earliest >= floor, Comment(rawValue:
                    "\(person.name) spans \(earliest)…\(latest), outside the \(person.recipe.days) days behind the anchor"))
        }

        // ── 3. Fifty-two weeks away is the same cohort, line for line.
        let aYearOn = try #require(calendar.date(byAdding: .day, value: 364, to: anchor))
        for person in SyntheticCohort.everyone {
            #expect(fingerprint(person.rebuilt(at: aYearOn)) == fingerprint(person), Comment(rawValue:
                    "\(person.name) came out different when the same recipe was built 52 weeks later"))
        }

        // ── 4. One day away, everybody changes.
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: anchor))
        for person in SyntheticCohort.everyone {
            #expect(fingerprint(person.rebuilt(at: tomorrow)) != fingerprint(person), Comment(rawValue:
                    "\(person.name) is unchanged by a one-day shift — the weekday channel this test exists for has gone"))
        }
    }
}
