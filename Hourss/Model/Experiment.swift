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
        self.premise = premise
        self.change = change
        self.caveat = caveat
        self.abandonedAt = abandonedAt
        self.settlement = settlement
        self.acknowledgedAt = acknowledgedAt
    }

    static let defaultWindowDays = 14

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
        let adherenceDays: Int
        /// Distinct days behind the baseline side.
        let baselineDays: Int
        /// Mean of the day means on each side. Day means rather than session means,
        /// because the bootstrap clusters on days and the figure shown has to be
        /// the figure that was tested.
        let focusFigure: Double
        let baselineFigure: Double
        /// Cliff's delta and its day-clustered interval, from `Statistics`.
        let delta: Double
        let intervalLow: Double
        let intervalHigh: Double
        let settledAt: Date
    }

    /// What an experiment can conclude.
    ///
    /// **Three cases, and the two unglamorous ones are not failure states.** An
    /// app whose tests always succeed is not running tests, and a person who can
    /// only ever be told they were right learns nothing. `didNotHoldUp` is a real
    /// result about their own life and is presented with the same weight as
    /// `heldUp`; `cannotTell` is a statement about the evidence and never about the
    /// person.
    enum Verdict: String, Hashable, Codable {
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
