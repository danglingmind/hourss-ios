import Foundation

/// Facts drawn from the record somebody kept, rather than from what their watch
/// read.
///
/// **Why this exists.** `HealthDigest` can only say what a year of Health
/// history holds: ten metrics, four generators, thirty-seven facts at the very
/// most, all of them computable on the day the app is installed and none of them
/// growing afterwards. `DailyFact` rations one a day, so the pool empties in
/// about five weeks and the app goes quiet again — the same silence the daily
/// fact was built to fill, arriving a month later. Nothing in that pipeline has
/// ever read a session.
///
/// This half grows. Every rated session is another row these generators can draw
/// a superlative from, so the person who logs gets more to read *because* they
/// logged, which is the whole thing the feature was supposed to do.
///
/// **What keeps it inside the trust model.** Every fact here is a superlative
/// inside one person's own record — arithmetic over their own rows, and nothing
/// else. "Your longest stretch so far" needs no evidence gate because it asserts
/// no relationship: it is one row being reported, not two things being claimed
/// to travel together. The moment a generator here needs two facts to be true at
/// once — that long sessions feel better, that mornings run longer — it has
/// become a claim about a relationship and it belongs to the engine, behind the
/// twelve-day floor and the correction. That line is not a matter of degree, and
/// it is the only rule this file has.
enum RecordFacts {

    /// Enough rated sessions for "so far" to mean anything.
    ///
    /// Below this, a superlative is arithmetic on a sample that has not had the
    /// chance to be beaten — "your longest of three" is true and says nothing.
    /// Five is the same floor `HealthDigest.minimumDaysPerSide` uses for one side
    /// of a comparison, chosen for the same reason and no deeper one.
    static let minimumSessions = 5

    /// Everything the record can say right now, ranked the way the Health pool is.
    ///
    /// Takes closures rather than the store, so this stays testable without a
    /// `HourssStore` and cannot reach for anything it was not handed.
    static func pool(
        sessions: [Session],
        feeling: (UUID) -> Int? = { _ in nil },
        activityName: (UUID) -> String,
        calendar: Calendar = .current
    ) -> [HealthDigest.Fact] {
        let eligible = sessions.filter { $0.isEligibleForPatterns && $0.healthKind != .sleep }
        guard eligible.count >= minimumSessions else { return [] }

        return [
            longestStretch(eligible, activityName: activityName),
            newestTimeOfDay(eligible, feeling: feeling, calendar: calendar),
            fullestDay(eligible, calendar: calendar),
        ].compactMap { $0 }
    }

    /// Why there is no streak generator.
    ///
    /// "Six days running" is descriptive and would pass every rule in this file,
    /// and it is still the wrong fact for this app to tell. A streak is a thing
    /// somebody can break, and the moment it exists the app has an opinion about
    /// how often you log — on a screen whose empty state reads "Whatever you're
    /// doing right now is enough." Every other fact here reports something that
    /// happened; a streak reports something you are at risk of losing. That is a
    /// different product, and adopting it should be a decision somebody makes out
    /// loud rather than a generator that arrives with four others.

    // MARK: - Generators

    /// The single longest block in the record.
    ///
    /// Imported sleep is excluded outright. A night is always the longest thing
    /// in a day and nobody logged it, so a fact naming it would report the
    /// watch's work as the person's and would say the same thing every time it
    /// fired. `isEligibleForPatterns` is the existing spelling of "a session the
    /// record should reason about", so this uses that rather than inventing a
    /// second rule.
    private static func longestStretch(
        _ eligible: [Session],
        activityName: (UUID) -> String
    ) -> HealthDigest.Fact? {
        // An exact tie in seconds resolves to the earlier session, every run.
        // Determinism is a tested property of the digest and this pool is sorted
        // into the same list. Written out rather than as a ternary inside the
        // closure, which the type checker gives up on.
        func beats(_ a: Session, _ b: Session) -> Bool {
            if a.durationSeconds != b.durationSeconds {
                return a.durationSeconds > b.durationSeconds
            }
            return a.startAt < b.startAt
        }
        guard let longest = eligible.sorted(by: beats).first else { return nil }

        let name = longest.intention ?? activityName(longest.activityId)

        return HealthDigest.Fact(
            figure: formatMinutes(longest.durationMinutes),
            // States the sample alongside the claim, which is the house
            // convention — `Narration` attaches "observed across N sessions" to
            // every sentence it composes, so a superlative says what it is a
            // superlative of rather than leaving the reader to assume.
            sentence: "\(name) is the longest single stretch in your record, "
                + "out of \(eligible.count) sessions.",
            kind: .best,
            mark: .none,
            // Hand-set, the way `scale` is. There is no effect size here — a
            // superlative has no second group to differ from — so this exists
            // only to order record facts against each other, and never to compete
            // with a Health fact's surprise. `DailyFact` keeps the pools apart.
            strength: 0.05,
            subject: .record(.length),
            // Nothing here runs against an expectation, because there is no prior
            // about somebody's own longest session. `raised` only feeds
            // `expectedness`, which returns neutral for an unknown pair.
            raised: true,
            // The session that holds it. A different session holding the record
            // is a different fact and should be dispensed again; the same one is
            // not, however many times the pool is rebuilt.
            revision: longest.id.uuidString
        )
    }

    /// The part of the day that has just been rated for the first time.
    ///
    /// This is the one generator that rewards filling a gap rather than setting a
    /// record, and it is here because the gap is what the engine is waiting for:
    /// every comparison it can make needs both sides, and somebody who rates only
    /// mornings gives it nothing to compare mornings against. Saying so plainly
    /// would be an instruction, which the phrasing rules forbid and which this
    /// app does not do. Noting that an afternoon now exists in the record is a
    /// fact about the record, and the reader can draw their own conclusion.
    private static func newestTimeOfDay(
        _ eligible: [Session],
        feeling: (UUID) -> Int?,
        calendar: Calendar
    ) -> HealthDigest.Fact? {
        let rated = eligible.filter { feeling($0.id) != nil }
        guard rated.count >= minimumSessions else { return nil }

        func bucket(_ session: Session) -> TimeBucket {
            TimeBucket.bucket(forHour: calendar.component(.hour, from: session.startAt))
        }

        // Earliest rated session in each bucket, so "newest" means the bucket
        // whose first entry arrived last — not the most recent session overall.
        var firstRated: [TimeBucket: Session] = [:]
        for session in rated.sorted(by: { $0.startAt < $1.startAt }) {
            let slot = bucket(session)
            if firstRated[slot] == nil { firstRated[slot] = session }
        }

        // Nothing to say when the record already covers everything: a bucket that
        // was filled months ago is not news, and there is no gap left to note.
        guard firstRated.count > 1, firstRated.count < TimeBucket.allCases.count else { return nil }

        let newest = firstRated
            .sorted { $0.value.startAt > $1.value.startAt }
            .first!
        let missing = TimeBucket.allCases.filter { firstRated[$0] == nil }

        return HealthDigest.Fact(
            figure: "\(firstRated.count) of \(TimeBucket.allCases.count)",
            sentence: "\(newest.key.label) is the newest part of the day in your "
                + "rated record. \(missing.map(\.label).joined(separator: " and ")) "
                + (missing.count == 1 ? "has" : "have") + " none yet.",
            kind: .best,
            mark: .none,
            strength: 0.05,
            subject: .record(.coverage),
            raised: true,
            // Which buckets are covered. Covering another one is a new fact;
            // logging more into the same ones is not.
            revision: firstRated.keys.map(\.rawValue).sorted().joined(separator: "-")
        )
    }

    /// The single day holding the most logged time.
    private static func fullestDay(
        _ eligible: [Session],
        calendar: Calendar
    ) -> HealthDigest.Fact? {
        var totals: [Date: Int] = [:]
        for session in eligible {
            let day = calendar.startOfDay(for: session.startAt)
            totals[day, default: 0] += session.durationMinutes
        }
        // Two days at least, or "your fullest day" is just "the day you logged".
        guard totals.count >= 2 else { return nil }

        func fuller(_ a: (key: Date, value: Int), _ b: (key: Date, value: Int)) -> Bool {
            if a.value != b.value { return a.value > b.value }
            return a.key < b.key
        }
        guard let top = totals.sorted(by: fuller).first else { return nil }

        return HealthDigest.Fact(
            figure: formatMinutes(top.value),
            sentence: "That is the most you have logged in one day, "
                + "across \(totals.count) days with anything in them.",
            kind: .best,
            mark: .none,
            strength: 0.05,
            subject: .record(.dayTotal),
            raised: true,
            revision: ISO8601DateFormatter.string(
                from: top.key, timeZone: .current, formatOptions: [.withFullDate])
        )
    }
}
