import Foundation

/// Facts drawn from the record somebody kept, rather than from what their watch
/// read.
///
/// **Why this exists.** `HealthDigest` can only say what a year of Health
/// history holds: ten metrics, three generators, thirty facts at the very most,
/// all of them computable on the day the app is installed and none of them
/// growing afterwards. (It was four generators and thirty-seven facts until the
/// totals card was removed for being a sum rather than an observation — see
/// `HealthDigest.Fact.Kind`. Taking cards away is a legitimate way to make the
/// rest better, and the seven it cost were the seven nobody would have missed.)
/// `DailyFact` rations one a day, so the pool empties in about five weeks and
/// the app goes quiet again — the same silence the daily fact was built to fill,
/// arriving a month later. Nothing in that pipeline has ever read a session.
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

    /// Enough distinct weeks for "more than any other week" to be more than "more
    /// than the other one".
    ///
    /// Three rather than the two `fullestDay` asks of days, because a week is a
    /// coarse bucket and the record has to contain a week nobody is standing in.
    /// With two weeks in the record, one of them is nearly always the week still
    /// in progress, so "your fullest week" would be decided by which week the
    /// reader happens to be in rather than by anything about the record. Three
    /// means at least two of them are finished.
    static let minimumWeeks = 3

    /// Enough distinct days for an extreme taken over the clock to be an extreme
    /// over anything.
    ///
    /// The same three `daysInARow` wants, for the same reason: on one day the
    /// earliest start is simply the first thing logged that day, which is a row
    /// being read out rather than a superlative.
    static let minimumDays = 3

    /// Enough kinds of activity for "the newest" to distinguish anything. On one,
    /// the newest activity is the only activity.
    static let minimumActivities = 2

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

        // Order is dispensation order, not a ranking. `DailyFact` offers this
        // list ahead of the Health pool and takes the first entry it has not
        // already spent, so where a generator sits decides which day somebody
        // meets it. New generators are appended rather than slotted in: the first
        // four are what the existing tests and the existing phones expect to see
        // first, and reordering them would hand a different fact to somebody
        // mid-rotation for no gain.
        return [
            longestStretch(eligible, activityName: activityName),
            newestTimeOfDay(eligible, feeling: feeling, calendar: calendar),
            fullestDay(eligible, calendar: calendar),
            daysInARow(eligible, calendar: calendar),
            fullestWeek(eligible, calendar: calendar),
            newestActivity(eligible, activityName: activityName),
            earliestStart(eligible, calendar: calendar),
        ].compactMap { $0 }
    }

    /// Why there is a streak generator, and what the objection to it bought.
    ///
    /// **The argument that used to stand here**, kept because it was right about
    /// the risk and is the reason `daysInARow` has the shape it has: "Six days
    /// running" is descriptive and would pass every rule in this file, and it is
    /// still the wrong fact for this app to tell. A streak is a thing somebody
    /// can break, and the moment it exists the app has an opinion about how often
    /// you log — on a screen whose empty state reads "Whatever you're doing right
    /// now is enough." Every other fact here reports something that happened; a
    /// streak reports something you are at risk of losing. That is a different
    /// product, and adopting it should be a decision somebody makes out loud
    /// rather than a generator that arrives alongside the others.
    ///
    /// **It was made out loud, and it went the other way.** The product owner
    /// read the paragraph above and asked for the generator anyway. That is their
    /// call and it is the decision; this note exists so the next person to read
    /// `daysInARow` finds the concern recorded rather than a generator that looks
    /// like nobody weighed it.
    ///
    /// **What the generator concedes to it**, which is everything that could be
    /// conceded without refusing the request:
    ///
    /// - It reports the **longest** run so far, never the current one. A longest
    ///   run is a superlative over the record exactly like every other fact here, and
    ///   history cannot be broken — a fortnight of logging nothing leaves it
    ///   standing at the number it reached. A *current* streak is the thing the
    ///   objection is actually about: a live number whose only movement is
    ///   downward, which a reader is implicitly being asked to protect. This is
    ///   the load-bearing concession and the one to defend if anything here is
    ///   ever revisited.
    /// - Nothing in the copy addresses the reader. No target, no goal, no
    ///   tomorrow, no continuing: the sentence states a count that happened and
    ///   stops. The copy sweep in `RecordFactsTests` holds it there, against the
    ///   same vocabulary lists `NarrationGuard` uses plus the words this fact in
    ///   particular could reach for.
    /// - The word "streak" never reaches the screen. The title is "Days in a row"
    ///   and the sentence says "run of consecutive days", because "streak" is the
    ///   word that carries the thing somebody can lose.
    /// - Nothing about it moves with the clock. The number comes from the days
    ///   the record holds and from nothing else, so it does not decay at midnight
    ///   and there is no moment at which the app notices a run has ended. That is
    ///   also what keeps it deterministic, which is a tested property.
    ///
    /// **What is left over**, honestly: a number that can grow is a number
    /// somebody can want to grow, and this app now has one. The shape above
    /// removes the app's side of that — it never asks — but it cannot remove the
    /// reader's.

    /// Where the line falls, and the four generators it refused.
    ///
    /// The header's rule — every fact is a superlative inside one person's own
    /// record — reads as settled and is not, because "superlative" does not say
    /// *what the maximum is taken over*. Four of the six generators proposed
    /// alongside the three below were rejected on it or on the streak note above,
    /// and the test that did the rejecting is written down here because every
    /// future proposal will be this argument again.
    ///
    /// **A superlative may be taken over time's own index. It may not be taken
    /// over a family the engine searches.** `InteractionCandidates.factors` builds
    /// the engine's factor space out of five families — time of day, activity,
    /// duration bucket, workday, and a health split — and each is a recurring
    /// category whose values the engine weighs against each other behind the
    /// twelve-day floor, the lift gate and the correction. A session, a day, a
    /// week are not categories; they are positions in time, each occurring once.
    /// "12 March holds your fullest day" generalises to nothing, because there is
    /// never another 12 March. "Mornings hold the most" generalises to every
    /// morning the reader has not had yet, which is a claim about a category —
    /// the engine's claim, made without the engine's evidence.
    ///
    /// Naming *which values of a family the record contains* is a different thing,
    /// and is allowed: `newestTimeOfDay` and `newestActivity` report presence and
    /// never put two values of one family on a scale. The question to ask of a
    /// proposed generator is not "is this a maximum" but "if this card is true,
    /// is there a sentence about the next morning I could read off it".
    ///
    /// Taking the rejected four in turn, since the reasons differ:
    ///
    /// - **The most logged part of the day this week.** This is the header's own
    ///   example of what is not allowed — "that mornings run longer" is named
    ///   there as a relational claim — and it is a time-family argmax exactly.
    ///   Narrowing it to one week makes it worse rather than better: a week holds
    ///   a handful of sessions, so the answer turns over constantly, and a card
    ///   that says mornings this week and evenings next week is an unstable claim
    ///   about a category rather than a fact about a record.
    ///
    /// - **The activity with the most time in it.** The same refusal, one family
    ///   over. It is the most tempting of the six, because it is nearly always
    ///   true and feels like a description rather than a claim — but it ranks the
    ///   values of `Factor.Family.activity` against each other on duration, which
    ///   is the first half of the question the engine spends its whole budget
    ///   gating. It is also the fact a time tracker's own screens already answer:
    ///   the Journal's day rows name the activity and its minutes, so the only
    ///   thing the card adds is the ranking, which is the part it may not do.
    ///
    /// - **Several rated sessions in a row at or above some rating.** Refused on
    ///   two grounds, the second of which is the serious one. First, ratings are
    ///   already spoken for and deliberately not here: `RatingMilestone` exists
    ///   because a five-point scale ties constantly, so the only unambiguous
    ///   question about a rating compares one session against everything logged
    ///   before it, which can only be asked at the moment of rating. Second, and
    ///   worse: this is the one generator in the set that can corrupt its own
    ///   input. A feeling is the only subjective number this app collects and the
    ///   engine's sole dependent variable, and a card that counts how many good
    ///   ones somebody has strung together hands them a reason to enter a good
    ///   one. Every other fact in this file reads a measurement the reader has no
    ///   motive to bend; that one would put a thumb on the scale the engine is
    ///   weighing with.
    ///
    /// - **The longest unlogged gap that has since been filled.** Refused, and
    ///   not on the superlative rule, which it passes cleanly — it is one
    ///   measurement over time's own index, arithmetically the same shape as
    ///   `daysInARow`. It is refused on the streak note above. The concession
    ///   that made a run of days admissible was that a *longest* run is history
    ///   and history cannot be broken; a longest gap is the mirror image, history
    ///   that cannot be mended, and the only thing it reports is the fortnight
    ///   somebody spent not opening this app. The screen it would land on has an
    ///   empty state reading "Whatever you're doing right now is enough". A card
    ///   two rows below it, measuring the absence, says the opposite in the same
    ///   scroll.

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
            // Says what it left out, because the screen it lands on contradicts
            // it otherwise. The date heading above reads "10h 45m logged across
            // 4 sessions" from `totalLoggedMinutes`, which counts every session
            // on the day including a night the watch recorded; this counts only
            // what somebody logged. Two different numbers both called "logged in
            // one day" read as a fault in the app, and the cheaper half of the
            // fix is the sentence that knows which one it is.
            sentence: "That is the most you have logged in one day, not counting "
                + "nights read from Health, across \(totals.count) days.",
            kind: .best,
            mark: .none,
            strength: 0.05,
            subject: .record(.dayTotal),
            raised: true,
            revision: ISO8601DateFormatter.string(
                from: top.key, timeZone: .current, formatOptions: [.withFullDate])
        )
    }

    /// The longest run of consecutive days the record covers.
    ///
    /// Read the note above the generators before changing anything here: the
    /// choice of *longest* over *current* is the whole of what makes this fact
    /// admissible in this file, and swapping it is not a refactor.
    ///
    /// Days are the unit, and `recordDay` is the app's spelling of which day a
    /// session belongs to — the same one Today and the Journal file by, so a run
    /// counted here matches the days somebody can see rows on. For the sessions
    /// that reach this function it resolves to the start day, because imported
    /// sleep never reaches it.
    ///
    /// **Imported sleep does not count toward a run, and the exclusion matters
    /// more here than anywhere else in this file.** A watch records a night
    /// whether or not anybody opened the app, so a run built from nights would be
    /// a run of days the person owned a charged watch, credited to them as a
    /// record they kept. It would also almost never break, which would make the
    /// number both large and meaningless. `pool` already filters on
    /// `isEligibleForPatterns`, the existing spelling of "a session the record
    /// should reason about", and this generator inherits it rather than inventing
    /// a second rule.
    private static func daysInARow(
        _ eligible: [Session],
        calendar: Calendar
    ) -> HealthDigest.Fact? {
        // Sorted out of a set, so the arithmetic below sees each day once and in
        // one order. Two sessions on a Tuesday are one Tuesday.
        let days = Set(eligible.map(\.recordDay)).sorted()
        // Three days at least. On two, the longest run is either one or two and
        // both readings are arithmetic on a record that has had no chance to be
        // anything else — the same reason `minimumSessions` exists.
        guard days.count >= 3 else { return nil }

        var longest = 1
        var current = 1
        for (previous, day) in zip(days, days.dropFirst()) {
            // Whole calendar days apart, not 86,400 seconds apart: the day a
            // clock change falls on is still the next day, and a run that
            // straddles a month or a year boundary is still a run.
            let gap = calendar.dateComponents([.day], from: previous, to: day).day ?? 0
            current = gap == 1 ? current + 1 : 1
            longest = max(longest, current)
        }
        // A record of scattered single days has no run in it, and "1 day in a
        // row" is not a fact. Nothing is said rather than something trivial.
        guard longest >= 2 else { return nil }

        return HealthDigest.Fact(
            figure: "\(longest) days",
            // A count that happened, stated the way every other fact here
            // states its own. No second person beyond the possessive naming whose record
            // it is, no imperative, and nothing about what comes next. "Run of
            // consecutive days" rather than "streak" — see the note above the
            // generators. The denominator is the house convention: a superlative
            // says what it is a superlative of.
            //
            // "Not counting nights read from Health" is the same disclosure
            // `fullestDay` makes and for the same reason: the day headings on the
            // screen this lands on count imported nights, so a run computed
            // without them has to say so or it reads as a fault in the app.
            sentence: "That is the longest run of consecutive days with something "
                + "logged on them, not counting nights read from Health, out of "
                + "\(days.count) days in your record.",
            kind: .best,
            mark: .none,
            strength: 0.05,
            subject: .record(.daysInARow),
            raised: true,
            // The count itself, and nothing else. A longer run than the last one
            // reported is a different fact and is dispensed again; the same
            // number is the same fact however often the pool is rebuilt. A second
            // run of equal length later in the record is the same number and so
            // not news, which is why the dates the run covers are deliberately
            // not in here: keying on them would re-dispense "your longest is
            // still four" every time four happened again, which is the nag this
            // fact was most at risk of becoming.
            revision: "\(longest)"
        )
    }

    /// The single week holding the most logged time.
    ///
    /// A week is the one window wider than a day that somebody can still hold in
    /// mind, and it is the window this app has no other way to speak about: Today
    /// shows a day, the Journal shows days in a list, and nothing anywhere adds
    /// seven of them up. The superlative is over time's own index — this week
    /// against every other week in the record — so it asserts nothing about any
    /// week to come. See the note above the generators for why that distinction is
    /// the whole of what makes this admissible and "the busiest part of your day"
    /// not.
    private static func fullestWeek(
        _ eligible: [Session],
        calendar: Calendar
    ) -> HealthDigest.Fact? {
        var totals: [Date: Int] = [:]
        for session in eligible {
            // The calendar's own week, not seven days counted back from
            // something. `firstWeekday` is regional — Monday in much of Europe,
            // Sunday in the US, Saturday in parts of the Gulf — and a week measured
            // from whichever day the record happens to open on would group the same
            // sessions differently for two people with identical logs, and would
            // regroup them for one person the moment an older session was added.
            // `dateInterval` is the only thing that knows where a week starts.
            guard let week = calendar.dateInterval(of: .weekOfYear, for: session.recordDay)?.start
            else { continue }
            totals[week, default: 0] += session.durationMinutes
        }
        guard totals.count >= minimumWeeks else { return nil }

        // Sorted, like every other dictionary in this file: an exact tie in
        // minutes resolves to the earlier week, every run. Determinism is a tested
        // property of the pool.
        func fuller(_ a: (key: Date, value: Int), _ b: (key: Date, value: Int)) -> Bool {
            if a.value != b.value { return a.value > b.value }
            return a.key < b.key
        }
        guard let top = totals.sorted(by: fuller).first else { return nil }

        return HealthDigest.Fact(
            figure: formatMinutes(top.value),
            // The same disclosure `fullestDay` makes, for a weaker but real
            // version of the same reason: no week total is printed anywhere in the
            // app, but the Journal's day rows are totals a reader can add up, and
            // those count a night the watch recorded. A week total that silently
            // used a different rule would read as a fault in the app.
            sentence: "That is more than any other week in your record, not "
                + "counting nights read from Health, out of \(totals.count) weeks.",
            kind: .best,
            mark: .none,
            strength: 0.05,
            subject: .record(.weekTotal),
            raised: true,
            // Which week holds it, and deliberately not how many minutes.
            //
            // Keying on the total would re-dispense this card on most days
            // somebody logs: the leading week is often the one they are standing
            // in, so its total grows every session and every growth would look
            // like a new fact. "Your fullest week" arriving six days running is
            // the nag this generator was most at risk of becoming. A different
            // week taking the lead is a genuinely different answer and is said
            // again; the same week getting fuller is the same answer.
            revision: ISO8601DateFormatter.string(
                from: top.key, timeZone: .current, formatOptions: [.withFullDate])
        )
    }

    /// The kind of activity that entered the record most recently.
    ///
    /// Presence, never magnitude — the sentence says an activity is the newest one
    /// in the record and nothing about how it compares with the others. That is
    /// the same shape as `newestTimeOfDay`, and it is why this is allowed where
    /// "the activity you spend the most time in" is not: activity is a family the
    /// engine searches over, so ranking its values on a measurement would be the
    /// engine's claim without the engine's gate, while listing which values exist
    /// is a fact about the record's own contents.
    ///
    /// It is also the generator most likely to fire for somebody new. Trying a
    /// second kind of activity happens in the first week; beating your own longest
    /// stretch may not happen for a month.
    private static func newestActivity(
        _ eligible: [Session],
        activityName: (UUID) -> String
    ) -> HealthDigest.Fact? {
        // Written out rather than as a comparator expression inline, which the
        // type checker gives up on — the same reason `longestStretch` has one.
        func earlier(_ a: Session, _ b: Session) -> Bool {
            if a.startAt != b.startAt { return a.startAt < b.startAt }
            // Two sessions starting in the same second cannot be allowed to make
            // "the first of this activity" depend on the order the store handed
            // the rows over.
            return a.id.uuidString < b.id.uuidString
        }

        // Grouped by `activityId` rather than by name. The id is what the record
        // stores, so renaming an activity does not mint a new kind — which is
        // right, and is also what stops a rename from re-dispensing this card as
        // though something new had been tried.
        var firstSession: [UUID: Session] = [:]
        for session in eligible.sorted(by: earlier) where firstSession[session.activityId] == nil {
            firstSession[session.activityId] = session
        }
        guard firstSession.count >= minimumActivities else { return nil }

        // The activity whose first session is the latest of those firsts. Sorted
        // out of `values` with the same comparator read backwards, so the answer
        // does not depend on dictionary order.
        guard let newest = firstSession.values.sorted(by: { earlier($1, $0) }).first
        else { return nil }

        // The activity's name, never the session's `intention`. `longestStretch`
        // prefers the intention because that fact is about one block and the
        // intention is what the person called it; this fact is about a kind of
        // activity that recurs, and a one-off label from whichever session
        // happened to be first would name something the next session of the same
        // activity does not answer to.
        let name = activityName(newest.activityId)

        return HealthDigest.Fact(
            figure: "\(firstSession.count)",
            sentence: "\(name) is the newest of the \(firstSession.count) kinds of "
                + "activity in your record, across \(eligible.count) sessions.",
            kind: .best,
            mark: .none,
            strength: 0.05,
            subject: .record(.activities),
            raised: true,
            // Both halves, because either can change on its own. A different
            // newest activity is plainly a new fact; so is a new count, which is
            // reachable without the newest changing — logging a past session
            // under an activity the record has never seen adds a kind whose first
            // session is old.
            revision: "\(firstSession.count)-\(newest.activityId.uuidString)"
        )
    }

    /// The earliest in a day that anything in the record was started.
    ///
    /// One row reported, the same shape as `longestStretch` with the clock in
    /// place of the duration, and admissible for the same reason: it names a
    /// session, not a category. It is here rather than its mirror — the latest
    /// finish — because a record of what somebody has done is the only thing this
    /// app can show that nothing else can, and an hour they once started at is a
    /// memory they cannot be asked to defend. Nothing about it can be lost: an
    /// earliest start is history, exactly like the longest run of days, and the
    /// concessions listed above `daysInARow` apply to it unchanged.
    private static func earliestStart(
        _ eligible: [Session],
        calendar: Calendar
    ) -> HealthDigest.Fact? {
        // Three days at least. Over one day the earliest start is just the first
        // thing logged that day — a row read out rather than a superlative over
        // anything — which is the same floor and the same reason as `daysInARow`.
        let days = Set(eligible.map(\.recordDay))
        guard days.count >= minimumDays else { return nil }

        // Minutes after midnight, in the calendar this pool was handed.
        //
        // The record stores instants and no timezone, so this is read wherever
        // the reader is standing: a 6am start in Tokyo is not 6am read back in
        // London. That limitation is already everywhere in the app — `recordDay`
        // decides which day a session belongs to the same way, and `TimeBucket`
        // buckets it the same way — and it is not fixable here. Fixing it means
        // putting a timezone on `Session`, which every surface that files by day
        // would have to agree about.
        func minuteOfDay(_ session: Session) -> Int {
            let parts = calendar.dateComponents([.hour, .minute], from: session.startAt)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }

        func earlier(_ a: Session, _ b: Session) -> Bool {
            let left = minuteOfDay(a), right = minuteOfDay(b)
            if left != right { return left < right }
            // Two sessions at the same clock minute on different days are a tie
            // this generator has to resolve the same way every run, so it falls
            // through to the instant and then to the id.
            if a.startAt != b.startAt { return a.startAt < b.startAt }
            return a.id.uuidString < b.id.uuidString
        }
        guard let first = eligible.sorted(by: earlier).first else { return nil }

        // Formatted through the calendar this generator computed in, rather than
        // through the autoupdating default. Those are the same thing in the app
        // and need not be in a test, and a figure that disagreed with the
        // arithmetic behind it would be the hardest kind of wrong to notice.
        let clock = Date.FormatStyle(date: .omitted, time: .shortened,
                                     calendar: calendar, timeZone: calendar.timeZone)

        return HealthDigest.Fact(
            figure: first.startAt.formatted(clock),
            sentence: "That is the earliest in a day you have started something, "
                + "out of \(days.count) days in your record.",
            kind: .best,
            mark: .none,
            strength: 0.05,
            subject: .record(.earliestStart),
            raised: true,
            // The clock minute, not the session holding it — the same choice
            // `daysInARow` makes and for the same reason. A second session
            // starting at the same minute months later is the same answer, and
            // keying on its id would re-dispense "your earliest is still 6:12"
            // as though something had happened.
            revision: "\(minuteOfDay(first))"
        )
    }
}
