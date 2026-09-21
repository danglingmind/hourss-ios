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
        activityName: (UUID) -> String
    ) -> [HealthDigest.Fact] {
        [
            longestStretch(sessions: sessions, activityName: activityName),
        ].compactMap { $0 }
    }

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
        sessions: [Session],
        activityName: (UUID) -> String
    ) -> HealthDigest.Fact? {
        let eligible = sessions.filter { $0.isEligibleForPatterns && $0.healthKind != .sleep }
        guard eligible.count >= minimumSessions else { return nil }

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
            // only to order record facts against each other once there is more
            // than one generator, and never to compete with a Health fact's
            // surprise. `DailyFact` keeps the two pools apart for that reason.
            strength: 0.05,
            subject: .record(.length),
            // Nothing here runs against an expectation, because there is no prior
            // about somebody's own longest session. `raised` only feeds
            // `expectedness`, which returns neutral for an unknown pair.
            raised: true
        )
    }
}
