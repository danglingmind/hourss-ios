import Foundation

/// A change this person agreed to make, and the window it is being judged over.
///
/// **Why this is stored when insights are not.** `RecordStore` keeps only what
/// belongs to the person rather than to the computation, and an insight is absent
/// from the record because the engine can recompute it from the sessions it came
/// from. A commitment is not in that position. Nothing in the sessions says that
/// somebody agreed, on a particular evening, to put one block in their morning for
/// a fortnight — that is a decision they made, it cannot be re-derived from
/// anything, and it is gone forever if it is not written down.
///
/// **Why the words are frozen with it.** `premise`, `change` and `caveat` are
/// copied in at acceptance rather than re-read from `HypothesisRegistry` when the
/// card is drawn. That looks like the stored-derived-value mistake and is the
/// opposite of it: what the person agreed to includes *what they were told they
/// were agreeing to*. Re-deriving the strings means a registry edit in some later
/// version silently rewrites the terms of a commitment somebody already made, and
/// a person reviewing a settled experiment is shown a change they never accepted.
/// The same argument licenses `Settlement`'s frozen figures below, and it is the
/// argument `Record.physiology` already makes for the heart-rate residual.
///
/// **What is deliberately not frozen: the predicate.** `Hypothesis.focus` is a
/// closure and could not be encoded anyway, so settling looks the hypothesis up in
/// the registry by `hypothesisId` and uses its live predicate to decide which
/// sessions qualified. That is the right way round — "morning" should mean
/// whatever the registry means by morning today, because the person was testing
/// their mornings and not a definition. The cost is that an experiment whose
/// hypothesis has left the registry can no longer be settled, which is a real case
/// — the activity it named may have been deleted — and is why `Verdict` has a
/// case for not being able to tell rather than treating absence as a failure.
struct Experiment: Identifiable, Hashable, Codable {
    /// This run's own identity, not the hypothesis's.
    ///
    /// A person may test the same thing again a year later, and those are two
    /// experiments with two results rather than one record being overwritten.
    let id: UUID

    /// The registry key, which is also how the predicate is found again at
    /// settling time. `Engine.identity(of:)` turns it into the insight UUID; the
    /// string is what is stored because it is the natural key and the UUID is
    /// derivable from it, never the reverse.
    let hypothesisId: String

    /// What is being measured. Only a directed outcome can be experimented on —
    /// see `ExperimentDesign` — so this is never `heartRateResidual`.
    let outcome: Outcome

    let startedAt: Date

    /// Fourteen by default. The engine's own per-side minimum is six distinct
    /// days, and a fortnight is the shortest window that gives a realistic shot at
    /// six qualifying ones without somebody forgetting they agreed to anything.
    let windowDays: Int

    /// The two sides, in the words the proposal used.
    let focusLabel: String
    let baselineLabel: String

    /// Which way the focus side is predicted to go, stated before the window opens.
    ///
    /// **This is the field the whole argument for experiments rests on.** A mined
    /// pattern needs a multiplicity correction because the engine searched sixty
    /// candidates and kept the best; a test needs none because its one prediction
    /// was fixed in advance and cannot be chosen to fit the data afterwards. That
    /// is only true if the direction is written down beforehand, and this is where
    /// it is written down. A verdict that decided after the fact which direction
    /// counted as success would be the fishing the correction exists to stop,
    /// wearing the clothes of a test.
    ///
    /// Almost always `true`: a proposal asks somebody to do more of something,
    /// so the group being grown is the one predicted to read higher. A test of
    /// moving a draining block somewhere better is still predicts-higher, because
    /// the focus group becomes the block in its new home.
    var predictsHigher: Bool = true

    /// Which days of the window carry the change, when the app chose them.
    ///
    /// **Nil is the whole of how an experiment carries its kind.** Phases 1 to 3
    /// compare the hypothesis's focus group against its baseline group inside one
    /// window, and the person decides which days do which — out-of-sample
    /// confirmation of a prediction fixed in advance, which is much stronger than
    /// mining and weaker than a trial, because anything that moved with their choice
    /// of days moved with the result. Nil says that is what this is. A value says the
    /// app drew the days before the window opened, so the assignment cannot
    /// correlate with how the days were going to go, and the comparison is between
    /// days the person did not pick.
    ///
    /// Optional rather than a `Kind` enum beside it for the reason `phase` is
    /// computed rather than stored: a kind field and an assignment field can
    /// disagree about whether there are days, and then one of them is wrong and
    /// nothing says which. There is one fact here — were days drawn — and one place
    /// it lives. The default is what keeps every existing construction site, and
    /// every record written at schema 3, meaning exactly what it meant before.
    ///
    /// Fixed at acceptance and never recomputed. `predictsHigher` records the
    /// direction before any data exists and this records the days; both have to be
    /// settled beforehand or the test is a search wearing a test's clothes.
    var assignment: Assignment?

    /// Why this was proposed — the premise, which is descriptive and claims
    /// nothing.
    let premise: String
    /// The one change, concrete enough to be checkable. This is the only string in
    /// the app permitted to instruct, and `ExperimentCopy` is where that is
    /// enforced.
    let change: String
    /// The limit on what a result here can mean. Carried for the same reason
    /// `Recommendation` carries one: a suggestion without its caveat would be the
    /// one place in the app a caveat could be dropped.
    let caveat: String

    /// Set when the person stopped early. Abandoning is free and uncounted — there
    /// is deliberately no record of *how often* somebody has done it, because that
    /// number has no use that is not a reproach.
    var abandonedAt: Date?

    /// Frozen at the moment the window closed. Nil while the window is open.
    var settlement: Settlement?

    /// Set once the person has seen the result, so a settled experiment stops
    /// claiming the slot on Today.
    var acknowledgedAt: Date?

    init(
        id: UUID = UUID(),
        hypothesisId: String,
        outcome: Outcome,
        startedAt: Date,
        windowDays: Int = Experiment.defaultWindowDays,
        focusLabel: String,
        baselineLabel: String,
        predictsHigher: Bool = true,
        assignment: Assignment? = nil,
        premise: String,
        change: String,
        caveat: String,
        abandonedAt: Date? = nil,
        settlement: Settlement? = nil,
        acknowledgedAt: Date? = nil
    ) {
        self.id = id
        self.hypothesisId = hypothesisId
        self.outcome = outcome
        self.startedAt = startedAt
        self.windowDays = windowDays
        self.focusLabel = focusLabel
        self.baselineLabel = baselineLabel
        self.predictsHigher = predictsHigher
        self.assignment = assignment
        self.premise = premise
        self.change = change
        self.caveat = caveat
        self.abandonedAt = abandonedAt
        self.settlement = settlement
        self.acknowledgedAt = acknowledgedAt
    }

    static let defaultWindowDays = 14

    /// Four weeks, for a window whose days are drawn rather than chosen.
    ///
    /// **Derived from the floor rather than picked.** A fortnight is the shortest
    /// window that gives a realistic shot at `minimumDays` qualifying days, and that
    /// reasoning is unchanged — but a randomised window hands only *half* its days to
    /// each side, so six on each side needs twice as many days to draw from. Fourteen
    /// days randomised is seven assigned and seven not: somebody would have to adhere
    /// on six of seven and also carry a rated session on six of the other seven, and
    /// anything less reports that it cannot be read. That is a month of somebody's
    /// life spent on a question the arithmetic already said could not be answered,
    /// which is the objection `ExperimentStarters.metricMinimumDays` makes about
    /// aiming a fortnight at a metric Health holds for four days.
    ///
    /// The alternative was keeping a fortnight and lowering the floor for randomised
    /// windows only. Refused: the floor is `Hypothesis.minimumDays`, borrowed rather
    /// than invented, and buying the stronger design with a weaker threshold would
    /// hand back more than it bought.
    static let randomisedWindowDays = 28

    /// Whether the app drew this window's days.
    ///
    /// Computed from the assignment rather than stored next to it, so the two cannot
    /// disagree about what kind of experiment this is.
    var isRandomised: Bool { assignment != nil }

    /// Distinct days required before a side can be read at all.
    ///
    /// Borrowed from `Hypothesis.minimumDays` rather than chosen here. Six sessions
    /// on one Tuesday are one day of evidence about Tuesdays, and an experiment is
    /// under exactly the same obligation as the engine on that point — adopting a
    /// looser floor for a test than for an observation would make the test the
    /// weaker instrument, which is backwards.
    static let minimumDays = 6
}

// MARK: - Phase

extension Experiment {

    /// Where this experiment is in its life.
    ///
    /// Computed from the three optionals rather than stored alongside them, so
    /// there is no second source of truth to disagree with them. A stored phase
    /// plus a stored `settlement` can contradict each other; this cannot.
    enum Phase: Equatable {
        /// Window open, nothing to report yet.
        case active
        /// Stopped early. Carries no verdict, because nothing was tested.
        case abandoned
        /// Window closed, verdict frozen, not yet seen.
        case settled
        /// Verdict seen. Keeps its figures and stops claiming the slot.
        case acknowledged
    }

    var phase: Phase {
        if abandonedAt != nil { return .abandoned }
        guard settlement != nil else { return .active }
        return acknowledgedAt == nil ? .settled : .acknowledged
    }

    /// The moment the window closes.
    ///
    /// Days rather than seconds, through the calendar, because a fortnight that
    /// crosses a daylight-saving boundary is still a fortnight and `startedAt +
    /// 14 * 86400` is not.
    func endsAt(calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: windowDays, to: startedAt) ?? startedAt
    }

    /// Whether the window has run out, which is a different question from whether
    /// the experiment has been settled — settling happens on the next launch or
    /// foreground after this becomes true, not at the instant itself.
    func hasClosed(at now: Date, calendar: Calendar = .current) -> Bool {
        now >= endsAt(calendar: calendar)
    }

    /// Whole days left, floored at zero. For the active card, which shows a count
    /// and never a deadline.
    func daysRemaining(at now: Date, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: now, to: endsAt(calendar: calendar)).day ?? 0
        return max(0, days)
    }

    /// The window as a date interval, for selecting the sessions that count.
    ///
    /// Half-open at the end so a session starting exactly at the closing instant
    /// belongs to the next window rather than to both.
    func window(calendar: Calendar = .current) -> Range<Date> {
        startedAt ..< max(startedAt, endsAt(calendar: calendar))
    }
}

// MARK: - Settlement

extension Experiment {

    /// What the window produced, frozen at the moment it closed.
    ///
    /// **Why these numbers are written down rather than recomputed.** The baseline
    /// is drawn from a rolling window of this person's own history, so re-deriving
    /// a settled experiment next month compares it against a different baseline and
    /// produces a different number for a fortnight that has not changed. A figure
    /// that moves between launches cannot be shown to anybody as a result, which is
    /// the whole of `Record.physiology`'s argument and applies here unaltered.
    struct Settlement: Hashable, Codable {
        let verdict: Verdict
        /// Distinct days in the window that carried a qualifying rated session.
        /// Reported as a count and never as a streak.
        ///
        /// For a randomised window this counts only the *assigned* days: whether the
        /// change happened when the app asked for it.
        let adherenceDays: Int
        /// Distinct days behind the side this was read against. The baseline group
        /// for a chosen window; the unassigned days for a drawn one.
        let baselineDays: Int
        /// Distinct days the change happened on when it had **not** been asked for.
        ///
        /// Nil for a chosen window, where the quantity is undefined — there are no
        /// unasked days, because every day was theirs to choose. Nil rather than zero
        /// so a card cannot read "no contamination" off an experiment that never had
        /// an assignment to break.
        ///
        /// Written down with the rest because it is part of the result: a window where
        /// the change happened on every day has no contrast left, and the reason a
        /// verdict could not be read belongs in the record alongside the verdict.
        let contaminationDays: Int?
        /// Mean of the day means on each side. Day means rather than session means,
        /// because the bootstrap clusters on days and the figure shown has to be
        /// the figure that was tested.
        ///
        /// For a randomised window these are the assigned and unassigned arms rather
        /// than the hypothesis's two groups, which is why `ExperimentCopy` does not
        /// name them with `focusLabel` there: the assigned arm includes days the
        /// person did not manage the change on, and calling that "Morning" would be a
        /// label the number does not carry.
        let focusFigure: Double
        let baselineFigure: Double
        /// Cliff's delta and its day-clustered interval, from `Statistics`.
        let delta: Double
        let intervalLow: Double
        let intervalHigh: Double
        let settledAt: Date

        /// Spelled out rather than synthesized so `contaminationDays` can default.
        ///
        /// A `let` with a default value is dropped from the memberwise initializer
        /// altogether, and a `var` would say a frozen figure can be edited, which is
        /// the one thing this type exists to deny. So the initializer is written.
        init(verdict: Verdict,
             adherenceDays: Int,
             baselineDays: Int,
             contaminationDays: Int? = nil,
             focusFigure: Double,
             baselineFigure: Double,
             delta: Double,
             intervalLow: Double,
             intervalHigh: Double,
             settledAt: Date) {
            self.verdict = verdict
            self.adherenceDays = adherenceDays
            self.baselineDays = baselineDays
            self.contaminationDays = contaminationDays
            self.focusFigure = focusFigure
            self.baselineFigure = baselineFigure
            self.delta = delta
            self.intervalLow = intervalLow
            self.intervalHigh = intervalHigh
            self.settledAt = settledAt
        }

        /// Unassigned days that carried a rated session and *not* the change — the
        /// only days a randomised result has to read against.
        ///
        /// Nil for a chosen window, which has no such notion. See
        /// `ExperimentOutcome` for why this rather than a contamination percentage
        /// is what gates the verdict.
        var contrastDays: Int? {
            contaminationDays.map { max(0, baselineDays - $0) }
        }
    }

    /// What an experiment can conclude.
    ///
    /// **Three cases, and the two unglamorous ones are not failure states.** An
    /// app whose tests always succeed is not running tests, and a person who can
    /// only ever be told they were right learns nothing. `didNotHoldUp` is a real
    /// result about their own life and is presented with the same weight as
    /// `heldUp`; `cannotTell` is a statement about the evidence and never about the
    /// person.
    /// `CaseIterable` so a suite can assert a property over every verdict rather
    /// than over the three that exist today. Without it the record screen's tests
    /// had to hand-list them and tie the list to an exhaustive switch, which works
    /// and is a workaround for a missing conformance word.
    enum Verdict: String, Hashable, Codable, CaseIterable {
        /// The interval on the difference excludes zero, in the favourable
        /// direction.
        case heldUp
        /// The interval includes zero, or the difference ran the other way. The
        /// change was made and did not land.
        case didNotHoldUp
        /// Not enough of the change happened to read, or not enough baseline to
        /// read it against, or the hypothesis is no longer in the registry.
        /// Deliberately not a verdict about the change.
        case cannotTell
    }
}

// MARK: - Assignment

extension Experiment {

    /// The days the app drew, and the seed it drew them with.
    ///
    /// **Why this is the one change in the feature that moves the claim.** Phases 1
    /// to 3 compare two groups inside one window, and the person decided which days
    /// went into which group. That is out-of-sample confirmation of a prediction
    /// fixed in advance — far better than mining a history — but whatever made them
    /// choose a morning on Tuesday travelled into the result with it, and a good
    /// fortnight is still a good fortnight. Drawing the days beforehand removes
    /// exactly that: a set chosen by a generator before any of the data exists
    /// cannot be correlated with how those days were going to go.
    ///
    /// **Drawn in pairs, not as a subset of the whole window.** The obvious scheme
    /// is to shuffle the window's days and take half, which is uniform over every
    /// half-sized subset. One of those subsets is the first fortnight, and another is
    /// the second — so the scheme that is most random in the abstract will sometimes
    /// hand back precisely the before-and-after comparison this design exists to
    /// avoid, with a fortnight of flu or deadline or holiday landing entirely in one
    /// arm. Taking one day at random out of each consecutive pair keeps the imbalance
    /// between the arms to at most one day at every point in the window, so a trend
    /// across the month contributes to both arms almost equally.
    ///
    /// What blocking costs is predictability: knowing one day is assigned says the
    /// other day of its pair is not. In a trial that would be a concealment failure
    /// worth refusing the scheme over. Here the person is handed the whole list
    /// before they start — they have to be, or they cannot follow it — so the
    /// information blocking leaks is information they already have, and the cost is
    /// nil while the protection against a time trend is real.
    ///
    /// **Stored, never recomputed.** The days are what somebody agreed to, so they
    /// are written down; re-deriving them from the seed on each launch would mean
    /// that any future change to the drawing — a different generator, pairs of three,
    /// a fixed first day — silently re-assigns the days of a window already running,
    /// on somebody else's phone, with no error anywhere. The seed is stored beside
    /// them so the draw remains auditable: `drawing(windowDays:seed:)` reproduces the
    /// set exactly, and a test asserts it. The days are authoritative and the seed is
    /// provenance; nothing at runtime reads the seed.
    struct Assignment: Hashable, Codable {

        /// What the days were drawn with. Provenance only.
        let seed: UInt64

        /// Offsets from the window's first day, sorted and all inside the window.
        ///
        /// Offsets rather than dates because the window's days are already defined
        /// relative to `startedAt` everywhere else — `window(calendar:)` and
        /// `endsAt(calendar:)` both count days through the calendar — and storing
        /// absolute dates would be a second description of the same fortnight, free
        /// to drift from the first across a daylight-saving boundary.
        let dayOffsets: [Int]

        /// How many days carry the change.
        var assignedCount: Int { dayOffsets.count }

        /// Whether a day of the window, counted from its first, carries the change.
        func isAssigned(dayOffset: Int) -> Bool { dayOffsets.contains(dayOffset) }

        /// Which day of the window a moment falls on, or nil for a moment outside it.
        ///
        /// Through calendar days on both sides, for the reason `endsAt` adds days
        /// rather than seconds: a window that crosses a clock change is still the
        /// same count of days, and an offset computed from elapsed seconds would be
        /// one out for half of it.
        func dayOffset(of moment: Date, startedAt: Date, windowDays: Int,
                       calendar: Calendar = .current) -> Int? {
            let from = calendar.startOfDay(for: startedAt)
            let to = calendar.startOfDay(for: moment)
            guard let days = calendar.dateComponents([.day], from: from, to: to).day,
                  days >= 0, days < windowDays else { return nil }
            return days
        }

        /// Whether a moment falls on an assigned day.
        func isAssigned(_ moment: Date, startedAt: Date, windowDays: Int,
                        calendar: Calendar = .current) -> Bool {
            guard let offset = dayOffset(of: moment, startedAt: startedAt,
                                         windowDays: windowDays, calendar: calendar)
            else { return false }
            return isAssigned(dayOffset: offset)
        }

        /// The assigned days as dates, for the list the person is shown.
        func assignedDates(startedAt: Date, calendar: Calendar = .current) -> [Date] {
            let first = calendar.startOfDay(for: startedAt)
            return dayOffsets.compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        }

        // MARK: Drawing

        /// One day out of each consecutive pair, drawn with `Statistics.Seeded`.
        ///
        /// `Seeded` rather than `SystemRandomNumberGenerator` because determinism is
        /// a tested property everywhere in this app that shows somebody a number: the
        /// bootstrap uses it so an interval cannot move between launches, and the same
        /// argument applies with more force to a set of days somebody is living by.
        ///
        /// An odd window leaves one day over, and it is drawn on its own — so the
        /// assigned count is half the window, rounded either way. Deliberate: the
        /// alternative is always assigning the orphan or never assigning it, and both
        /// make one particular day of the window special for a reason that has
        /// nothing to do with the person.
        static func drawing(windowDays: Int, seed: UInt64) -> [Int] {
            guard windowDays > 0 else { return [] }
            var generator = Statistics.Seeded(seed: seed)
            var offsets: [Int] = []
            var day = 0
            while day + 1 < windowDays {
                offsets.append(Bool.random(using: &generator) ? day : day + 1)
                day += 2
            }
            // The odd day out, when there is one.
            if day < windowDays, Bool.random(using: &generator) { offsets.append(day) }
            return offsets
        }

        /// A seed from the commitment itself.
        ///
        /// **Not `hashValue`, and this is the trap.** Swift's hashing is seeded per
        /// process, so a seed taken from `hypothesisId.hashValue` would be a different
        /// number on the next launch and the draw would be unreproducible — which
        /// matters not because anything recomputes it (nothing does) but because an
        /// unauditable number should not be the thing that decided somebody's month.
        /// FNV-1a over the bytes is stable across launches, devices and versions.
        ///
        /// **Why these two inputs.** The id alone would hand every person testing
        /// their mornings the identical pattern of days, and since people accept on
        /// the days they happen to be reading the app, a fixed pattern would line up
        /// with the weekday they started on — assigning Mondays, Wednesdays and
        /// Fridays to one arm across a whole population of Monday-evening acceptances.
        /// Weekday is one of the things this app measures. Mixing the start instant in
        /// breaks that without making the draw depend on anything about how the days
        /// were going.
        ///
        /// Taken to the second, and masked to 48 bits. The record encodes dates as
        /// ISO 8601 without fractional seconds, so a seed mixed from sub-second
        /// precision could not be checked against the stored days after a reload;
        /// and 48 bits is inside the range every JSON number path represents exactly,
        /// so the seed survives the file whatever decodes it. Both are about the seed
        /// still being the seed tomorrow.
        static func seed(hypothesisId: String, startedAt: Date) -> UInt64 {
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            func mix(_ byte: UInt8) {
                hash ^= UInt64(byte)
                hash = hash &* 0x100_0000_01b3
            }
            for byte in hypothesisId.utf8 { mix(byte) }
            let seconds = Int64(startedAt.timeIntervalSince1970.rounded())
            let bits = UInt64(bitPattern: seconds)
            for shift in stride(from: 0, through: 56, by: 8) {
                mix(UInt8(truncatingIfNeeded: bits >> UInt64(shift)))
            }
            return hash & 0xffff_ffff_ffff
        }

        /// The assignment for a window about to open.
        ///
        /// The only way one is made. Called once, at acceptance, with the same `now`
        /// that becomes `startedAt` — never a second read of the clock, which is a bug
        /// this codebase has already shipped once in the slot picker and would show up
        /// here as a day list that does not line up with the window it belongs to.
        static func make(hypothesisId: String, startedAt: Date, windowDays: Int) -> Assignment {
            let seed = seed(hypothesisId: hypothesisId, startedAt: startedAt)
            return Assignment(seed: seed,
                              dayOffsets: drawing(windowDays: windowDays, seed: seed).sorted())
        }
    }
}
