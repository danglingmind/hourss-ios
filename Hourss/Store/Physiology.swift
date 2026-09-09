import Foundation

/// Layer 3: movement-adjusted heart-rate physiology.
///
/// Heart rate rises for two unrelated reasons — movement, and everything else.
/// The product wants to be able to say "your heart rate ran higher than usual for
/// that hour, with almost no movement to explain it", and must never say "that
/// meeting was intense". The first is a measurement. The second is a claim about
/// a person's mind that no wrist sensor can support.
///
/// An earlier design used a binary gate: any steps in the window, discard the
/// session. That throws away the most interesting case there is — the person who
/// was walking *and* whose heart rate still ran higher than the walking accounts
/// for. So instead of gating, decompose:
///
/// ```
/// cadence   = steps in window ÷ minutes      // pace, not total
/// expected  = HR(cadence, hour band, day type)
/// explained = expected(cadence) − expected(0)
/// residual  = observed − expected
/// ```
///
/// Cadence rather than a step total because 400 steps in five minutes and 400 in
/// fifty are different events, and only the first has any bearing on heart rate.
///
/// Three cases fall out, and all three stay distinguishable:
///
/// | cadence | residual  | what it means                          |
/// |---------|-----------|----------------------------------------|
/// | high    | ~0        | movement explains it — say nothing     |
/// | ~0      | positive  | nothing explains it — worth showing    |
/// | high    | positive  | movement explains part — worth showing |
///
/// ## Why heart rate is the only candidate
///
/// Heart rate is the only *dense* type Apple Health carries: every few minutes at
/// rest, every few seconds in a workout. It is therefore the only signal that can
/// be attributed to a single session at all.
///
/// - **HRV (SDNN) is far too sparse.** A handful of samples a day, almost all of
///   them overnight or during a Breathe session. Querying it hourly returns mostly
///   empty windows, and the windows that are not empty are selected by *when the
///   watch chose to measure* rather than by anything about the person. HRV keeps
///   only its existing job: one overnight value associated with the following
///   morning. There is no per-session HRV here and there must not be.
/// - **Resting heart rate is one value per day by Apple's own construction.** It
///   is a derived daily figure, not a stream we chose to aggregate daily, so it
///   cannot be windowed however we query it.
/// - **Steps and active energy are dense**, and are the movement covariates.
///
/// ## What this layer is not allowed to produce
///
/// A number and a movement context. Never a judgement. Nothing here may state or
/// imply stress, intensity, effort, or emotion — `Outcome.heartRateResidual` is
/// deliberately undirected for the same reason, because a heart rate higher than
/// movement explains is not "bad" and saying so would be a medical claim.
///
/// ## The confounder that cannot be solved
///
/// Sometimes a person walks *because* a meeting is difficult. Pacing the corridor
/// is then a consequence of the very thing being measured, not an alternative
/// explanation for it, and subtracting the movement removes real signal along with
/// the artifact. Nothing in step and heart-rate data distinguishes that person from
/// one who simply takes their calls on foot: both produce high cadence and an
/// elevated heart rate in the same window. The residual will read near zero in both
/// cases. This is not a tuning problem — the two situations are identical in the
/// data — and it is why the output is a movement context rather than an
/// explanation, and why the wording is "movement accounts for it", not "it was
/// nothing".
///
/// The curve compounds this, because it is fitted from the same person's own
/// windows: someone whose only fast walking happens during meetings has a curve
/// that learned "walking" and "meetings" as one thing. Their high-cadence
/// residuals are near zero by construction. That is the honest answer given what
/// was measured, and it is why `Reading.uncertainty` widens with cadence instead
/// of narrowing.
enum Physiology {

    // MARK: - Inputs

    /// One measurement at its real timestamp.
    ///
    /// The existing daily path collapses everything through
    /// `intervalComponents: DateComponents(day: 1)`, which is our choice and not an
    /// API limit. Nothing in this file can work from that shape.
    struct Sample: Sendable, Equatable {
        let at: Date
        let value: Double

        init(at: Date, value: Double) {
            self.at = at
            self.value = value
        }
    }

    /// Everything one fit reads. Assembled by the caller so this file touches no
    /// service and is testable without HealthKit.
    struct Feed: Sendable {
        var heartRate: [Sample]
        /// Step counts at their own timestamps. Each sample is a total for the
        /// interval it covers; cadence divides the summed total by window minutes.
        var steps: [Sample]
        /// Windows of vigorous activity, used only for lead-in exclusion. Workouts
        /// are the reliable source; a cadence heuristic covers running that was
        /// never logged as a workout, and covers nothing that is not foot-borne.
        var vigorous: [DateInterval]

        init(heartRate: [Sample] = [], steps: [Sample] = [], vigorous: [DateInterval] = []) {
            self.heartRate = heartRate
            self.steps = steps
            self.vigorous = vigorous
        }

        var isEmpty: Bool { heartRate.isEmpty }
    }

    /// A stretch of time to attribute physiology to. Usually a logged session.
    struct Window: Sendable, Hashable {
        let id: UUID
        let start: Date
        let end: Date

        init(id: UUID = UUID(), start: Date, end: Date) {
            self.id = id
            self.start = start
            self.end = end
        }

        /// Nil for a running session: an open-ended window has no cadence, because
        /// the denominator keeps growing while you look at it.
        init?(session: Session) {
            guard let end = session.endAt else { return nil }
            self.init(id: session.id, start: session.startAt, end: end)
        }

        /// Fixed slices covering everything the sensors recorded, logged or not.
        ///
        /// The curve describes how this person's heart responds to moving, which
        /// is a fact about them rather than about their logging. Fitting it only
        /// on logged sessions wastes the overwhelming majority of the day and
        /// makes the curve hostage to a habit: someone who walks constantly but
        /// rarely logs walks would have no brisk windows to learn from, and the
        /// layer would then refuse to score anything — safe, and useless.
        ///
        /// Slices are aligned to the hour so two runs over the same history
        /// produce the same windows; tiling from the first sample would shift
        /// every boundary whenever the earliest reading changed.
        static func tiling(_ feed: Feed, minutes: Int = 30) -> [Window] {
            guard let first = feed.heartRate.min(by: { $0.at < $1.at })?.at,
                  let last = feed.heartRate.max(by: { $0.at < $1.at })?.at,
                  minutes > 0 else { return [] }

            let step = TimeInterval(minutes * 60)
            let origin = Date(timeIntervalSinceReferenceDate:
                                (first.timeIntervalSinceReferenceDate / step).rounded(.down) * step)

            var windows: [Window] = []
            var start = origin
            while start < last {
                let end = start.addingTimeInterval(step)
                windows.append(Window(start: start, end: end))
                start = end
            }
            return windows
        }

        /// Floored at one minute so cadence cannot divide by ~zero.
        var minutes: Double { max(end.timeIntervalSince(start) / 60, 1) }
    }

    // MARK: - Cadence

    /// Pace bands. Bins rather than a continuous fit because a person supplies a
    /// few hundred windows, not a few thousand, and a median inside a bin survives
    /// the outliers that a least-squares slope would chase.
    enum CadenceBin: Int, CaseIterable, Comparable, Sendable {
        /// Nothing recorded. Sitting.
        case still
        /// 1–20 steps/min. Shifting in a chair, a trip to the kettle.
        case minimal
        /// 20–60. Moving about, not going anywhere.
        case strolling
        /// 60–100. Walking.
        case brisk
        /// 100+. Walking fast, or faster.
        case fast

        static func containing(_ cadence: Double) -> CadenceBin {
            switch cadence {
            case ..<1: .still
            case ..<20: .minimal
            case ..<60: .strolling
            case ..<100: .brisk
            default: .fast
            }
        }

        static func < (lhs: CadenceBin, rhs: CadenceBin) -> Bool { lhs.rawValue < rhs.rawValue }

        /// How much movement there was, said plainly. Descriptive only: none of
        /// these may carry an implication about why the heart rate did what it did.
        var context: String {
            switch self {
            case .still: "with no movement recorded"
            case .minimal: "with almost no movement"
            case .strolling: "while moving around a little"
            case .brisk: "while walking"
            case .fast: "while walking quickly"
            }
        }
    }

    /// Hour band crossed with day type. Heart rate has a circadian shape and a
    /// different one on days off, so a window is only ever compared against the
    /// person's own windows from the same corner of the week.
    struct Cell: Hashable, Sendable {
        let band: TimeBucket
        let isWorkday: Bool
    }

    // MARK: - A summarised window

    /// One window reduced to the few numbers the curve is fitted on.
    struct WindowSummary: Sendable {
        let windowId: UUID
        /// Start of the calendar day, so the fit can count days rather than
        /// windows when it asks whether there is enough history.
        let day: Date
        /// Median bpm across the window. Median, not mean: a single motion artifact
        /// spike of 160 bpm moves a mean of six samples by fifteen beats.
        let heartRate: Double
        let sampleCount: Int
        let cadence: Double
        let band: TimeBucket
        let isWorkday: Bool

        var bin: CadenceBin { .containing(cadence) }
        var cell: Cell { Cell(band: band, isWorkday: isWorkday) }
    }

    // MARK: - The fitted curve

    /// This person's own heart rate as a function of their own pace.
    ///
    /// Fitted per person and never across people. A population curve would answer
    /// "is this person's heart rate high for a human", which is a medical question
    /// this product does not ask and is not equipped to answer.
    ///
    /// The shape is: a **baseline** per (hour band, day type), taken from the
    /// person's least-moving windows, plus a **lift** that is a function of cadence
    /// alone, pooled across cells.
    ///
    /// The pooling is not laziness. Five cadence bins × four hour bands × two day
    /// types is forty cells, and somebody logging three sessions a day for three
    /// months fills perhaps a third of them — most with one or two windows. Fitting
    /// a separate cadence curve per cell would produce forty medians of two, which
    /// is a curve fitted to noise. Splitting it this way spends the scarce
    /// high-cadence windows on the one thing they are needed for.
    struct MovementCurve: Sendable {

        /// A point the lift passes through: the bin's own median cadence, and the
        /// median amount the heart rate sat above baseline there.
        struct Knot: Sendable {
            let cadence: Double
            let lift: Double
        }

        // MARK: Evidence bars
        //
        // Below these the answer is nil. A curve fitted on less is not a weaker
        // answer, it is a different number with the same name.

        /// Windows required before a curve exists at all.
        static let minimumWindows = 20
        /// Distinct days those windows must span. Twenty windows from four days is
        /// four days of evidence about this person, not twenty.
        static let minimumDays = 10
        /// Windows a cadence bin needs before it becomes a knot.
        static let minimumWindowsPerBin = 4
        /// Windows the reference bin needs, since every baseline rests on it.
        static let minimumReferenceWindows = 8
        /// Windows a (band, day type) cell needs before it gets its own baseline
        /// rather than borrowing the day type's or the person's overall one.
        static let minimumWindowsPerCell = 4

        private let cellBaselines: [Cell: Double]
        private let dayTypeBaselines: [Bool: Double]
        private let overallBaseline: Double
        /// Ordered by cadence, anchored so `lift(0) == 0`.
        private let knots: [Knot]

        /// The lowest-cadence bin with enough windows to anchor on. Usually
        /// `.still` or `.minimal`; for someone who is never at rest during a
        /// logged session it may be higher, in which case everything below it is
        /// flat-extrapolated and `explained` understates. Documented rather than
        /// corrected, because there is no data to correct it with.
        let referenceBin: CadenceBin
        /// The highest bin an actual knot was fitted in. Above this the curve is
        /// guessing, and refuses instead.
        let fittedCeiling: CadenceBin
        /// This person's own scatter at rest, in bpm. The floor under every
        /// uncertainty figure — a residual smaller than the noise it sits in is not
        /// a finding.
        let referenceSpread: Double
        let windowCount: Int
        let dayCount: Int

        // MARK: Fitting

        /// Returns nil when there is not enough history to fit anything. Guessing a
        /// curve and then reporting residuals against it would produce confident
        /// numbers about nothing, which is the failure mode this whole engine
        /// exists to remove.
        static func fit(_ windows: [WindowSummary]) -> MovementCurve? {
            guard windows.count >= minimumWindows else { return nil }
            let days = Set(windows.map(\.day))
            guard days.count >= minimumDays else { return nil }

            var byBin: [CadenceBin: [WindowSummary]] = [:]
            for window in windows { byBin[window.bin, default: []].append(window) }

            guard let referenceBin = CadenceBin.allCases.first(where: {
                (byBin[$0]?.count ?? 0) >= minimumReferenceWindows
            }) else { return nil }

            let reference = byBin[referenceBin] ?? []
            guard let overall = median(reference.map(\.heartRate)) else { return nil }

            var byCell: [Cell: [Double]] = [:]
            var byDayType: [Bool: [Double]] = [:]
            for window in reference {
                byCell[window.cell, default: []].append(window.heartRate)
                byDayType[window.isWorkday, default: []].append(window.heartRate)
            }
            let dayTypeBaselines = byDayType.compactMapValues {
                $0.count >= minimumWindowsPerCell ? median($0) : nil
            }
            let cellBaselines = byCell.compactMapValues {
                $0.count >= minimumWindowsPerCell ? median($0) : nil
            }

            func baseline(_ cell: Cell) -> Double {
                cellBaselines[cell] ?? dayTypeBaselines[cell.isWorkday] ?? overall
            }

            // The lift is fitted on deviations from each window's own cell, which
            // is what lets bands with too little data still contribute to the
            // cadence curve without dragging their circadian offset into it.
            var knots: [Knot] = []
            for bin in CadenceBin.allCases where bin >= referenceBin {
                guard let group = byBin[bin], group.count >= minimumWindowsPerBin else { continue }
                guard let cadence = median(group.map(\.cadence)),
                      let lift = median(group.map { $0.heartRate - baseline($0.cell) })
                else { continue }
                knots.append(Knot(cadence: cadence, lift: lift))
            }
            guard let anchor = knots.first else { return nil }

            // Anchored on the reference bin so `lift(0)` is exactly zero and
            // `explained` is a difference from standing still rather than from
            // whatever the lowest bin happened to median out at.
            var anchored = knots.map { Knot(cadence: $0.cadence, lift: $0.lift - anchor.lift) }
            anchored.sort { $0.cadence < $1.cadence }

            let deviations = reference.map { $0.heartRate - baseline($0.cell) }
            let spread = min(max((medianAbsoluteDeviation(deviations) ?? 0) * 1.4826, 1.5), 12)

            return MovementCurve(
                cellBaselines: cellBaselines,
                dayTypeBaselines: dayTypeBaselines,
                overallBaseline: overall,
                knots: anchored,
                referenceBin: referenceBin,
                fittedCeiling: CadenceBin.containing(anchored.last?.cadence ?? 0),
                referenceSpread: spread,
                windowCount: windows.count,
                dayCount: days.count
            )
        }

        // MARK: Reading the curve

        func baseline(for cell: Cell) -> Double {
            cellBaselines[cell] ?? dayTypeBaselines[cell.isWorkday] ?? overallBaseline
        }

        /// Beats per minute this pace adds, relative to standing still. Piecewise
        /// linear between bin medians, flat outside them — a straight line through
        /// two bins is already more shape than the evidence supports, and an
        /// extrapolated slope beyond the last one would be pure invention.
        func explained(atCadence cadence: Double) -> Double {
            guard let first = knots.first, let last = knots.last else { return 0 }
            if cadence <= first.cadence { return first.lift }
            if cadence >= last.cadence { return last.lift }
            for (lower, upper) in zip(knots, knots.dropFirst()) where cadence <= upper.cadence {
                let span = upper.cadence - lower.cadence
                guard span > 0 else { return upper.lift }
                let t = (cadence - lower.cadence) / span
                return lower.lift + t * (upper.lift - lower.lift)
            }
            return last.lift
        }

        /// Whether this pace is inside what the curve actually saw.
        ///
        /// Above the fitted ceiling there is no evidence for how much of the rise
        /// the movement bought, so the residual would be "observed minus the last
        /// thing we knew about", reported as though it meant something. Real
        /// movement outside the fitted range returns nil instead. Paces below the
        /// ceiling are fine: flat-extrapolating downward toward stillness is
        /// conservative — it credits movement with less, never more.
        func canExplain(cadence: Double) -> Bool {
            let bin = CadenceBin.containing(cadence)
            if bin <= fittedCeiling { return true }
            // Nothing above the ceiling, but nothing worth explaining either.
            return bin < .strolling
        }
    }

    // MARK: - A result

    /// One window's physiology, decomposed. Carries every term so a caller can say
    /// how much movement there was rather than only that it was accounted for, and
    /// so a claim and its numbers cannot drift apart.
    struct Reading: Sendable {
        let windowId: UUID
        /// Median bpm measured in the window.
        let observed: Double
        /// What this person's own pace, hour and day type predict.
        let expected: Double
        /// How much of `expected` the movement bought, over standing still.
        let explainedByMovement: Double
        /// `observed − expected`. The number this layer exists to produce.
        let residual: Double
        let cadence: Double
        let cadenceBin: CadenceBin
        let sampleCount: Int
        /// How wide the honest error bar is, in bpm. See `Analyzer.uncertainty`.
        let uncertainty: Double

        /// Whether the residual clears its own error bar. Anything that does not
        /// is a number, not a finding, and must not be shown as one.
        var exceedsUncertainty: Bool { abs(residual) > uncertainty }

        /// The movement half of the output, in words. Descriptive by construction:
        /// there is deliberately no property here that names a cause, because
        /// callers reach for whatever is offered.
        var movementContext: String { cadenceBin.context }
    }

    // MARK: - The analyzer

    /// Turns a feed plus a person's windows into residuals.
    ///
    /// Pure: no HealthKit, no store, no clock beyond the dates it is handed.
    struct Analyzer: Sendable {

        /// Heart-rate samples a window needs before it is summarised at all.
        ///
        /// Five is low enough to keep a forty-minute window at rest and high enough
        /// that one motion artifact cannot become the median. A window with two
        /// samples has a heart rate in the same sense that two coin flips have a
        /// probability.
        static let minimumHeartRateSamples = 5

        /// A lower floor for windows that only contribute to the fit.
        ///
        /// The floor of five exists so that *one* session's residual is worth
        /// showing to somebody. A fitting window is pooled with hundreds of others
        /// and its noise averages out, so demanding the same of it discards
        /// evidence for a standard that does not apply.
        ///
        /// It is not free: fewer samples make each window's heart rate and cadence
        /// noisier, and noise in cadence attenuates the fitted lift toward zero.
        /// Three is a floor rather than a target, and the effect runs in the
        /// conservative direction — an attenuated curve under-explains movement
        /// and so leaves residuals larger, never smaller.
        static let minimumSamplesForFitting = 3

        /// How far back a session's baseline can be spoiled by exercise.
        ///
        /// Heart rate stays elevated for thirty to sixty minutes after vigorous
        /// activity and comes down on its own schedule, not one we can model from
        /// steps. A session in that shadow returns nil rather than a corrected
        /// value: the baseline is contaminated, not correctable, and a "corrected"
        /// number here would be the layer inventing exactly the kind of confident
        /// figure it exists to prevent.
        static let leadInMinutes: Double = 45

        /// Cadence over the lead-in that counts as vigorous on its own.
        ///
        /// Set above walking on purpose. Brisk walking is 100–120 steps a minute,
        /// so a threshold under that would void every session that follows a walk
        /// from the car park — which is not the contamination being guarded
        /// against, and would silently delete most of the interesting windows for
        /// anyone who takes their calls on foot. Running is 150–180. This catches
        /// nothing that is not foot-borne: cycling and rowing produce no steps at
        /// all, which is why logged workouts are the primary signal and this is the
        /// fallback.
        static let vigorousCadence: Double = 130

        let curve: MovementCurve?

        private let heartRate: [Sample]
        private let steps: [Sample]
        private let vigorous: [DateInterval]
        private let calendar: Calendar
        private let workdays: Set<Int>

        /// - Parameter fittingWindows: the person's own history. The curve is
        ///   fitted from these and nothing else.
        init(
            feed: Feed,
            fittingWindows: [Window],
            calendar: Calendar = .current,
            workdays: Set<Int> = [2, 3, 4, 5, 6]
        ) {
            let heartRate = feed.heartRate.sorted { $0.at < $1.at }
            let steps = feed.steps.sorted { $0.at < $1.at }
            self.heartRate = heartRate
            self.steps = steps
            self.vigorous = feed.vigorous
            self.calendar = calendar
            self.workdays = workdays

            // Windows excluded from scoring are excluded from fitting too. A
            // post-exercise window carries the exercise's heart rate at the
            // session's cadence, so leaving it in teaches the curve that sitting
            // still costs ninety beats a minute.
            let summaries = fittingWindows.compactMap {
                Analyzer.summarize(
                    $0,
                    heartRate: heartRate,
                    steps: steps,
                    vigorous: feed.vigorous,
                    calendar: calendar,
                    workdays: workdays,
                    minimumSamples: Analyzer.minimumSamplesForFitting
                )
            }
            self.curve = MovementCurve.fit(summaries)
        }

        /// The ordinary entry point: fit on the whole recorded day, score the
        /// sessions.
        ///
        /// Tiles rather than sessions, for the reason given on `Window.tiling`.
        /// The sessions are included as well because a logged window is a real
        /// observation of the same relationship, and dropping it to keep the input
        /// tidy would discard evidence for no gain.
        init(
            feed: Feed,
            sessions: [Session],
            tileMinutes: Int = 30,
            calendar: Calendar = .current,
            workdays: Set<Int> = [2, 3, 4, 5, 6]
        ) {
            let logged = sessions.filter(\.isEligibleForPatterns).compactMap(Window.init(session:))
            self.init(
                feed: feed,
                fittingWindows: Window.tiling(feed, minutes: tileMinutes) + logged,
                calendar: calendar,
                workdays: workdays
            )
        }

        // MARK: Summarising

        func summary(for window: Window) -> WindowSummary? {
            Analyzer.summarize(
                window,
                heartRate: heartRate,
                steps: steps,
                vigorous: vigorous,
                calendar: calendar,
                workdays: workdays
            )
        }

        /// Static so the initialiser can fit the curve before `self` exists.
        private static func summarize(
            _ window: Window,
            heartRate: [Sample],
            steps: [Sample],
            vigorous: [DateInterval],
            calendar: Calendar,
            workdays: Set<Int>,
            minimumSamples: Int = minimumHeartRateSamples
        ) -> WindowSummary? {
            guard window.end > window.start else { return nil }
            guard !isContaminated(before: window.start, steps: steps, vigorous: vigorous) else { return nil }

            let beats = slice(heartRate, from: window.start, to: window.end).map(\.value)
            guard beats.count >= minimumSamples, let centre = median(beats) else { return nil }

            let stepTotal = slice(steps, from: window.start, to: window.end).reduce(0) { $0 + $1.value }
            let weekday = calendar.component(.weekday, from: window.start)
            let hour = calendar.component(.hour, from: window.start)

            return WindowSummary(
                windowId: window.id,
                day: calendar.startOfDay(for: window.start),
                heartRate: centre,
                sampleCount: beats.count,
                cadence: stepTotal / window.minutes,
                band: TimeBucket.bucket(forHour: hour),
                isWorkday: workdays.contains(weekday)
            )
        }

        /// Whether the forty-five minutes before this window contain vigorous
        /// activity, from either a logged workout or a running-level cadence.
        static func isContaminated(
            before start: Date,
            steps: [Sample],
            vigorous: [DateInterval]
        ) -> Bool {
            let from = start.addingTimeInterval(-leadInMinutes * 60)
            let leadIn = DateInterval(start: from, end: start)
            if vigorous.contains(where: { $0.intersects(leadIn) }) { return true }
            let total = slice(steps, from: from, to: start).reduce(0) { $0 + $1.value }
            return total / leadInMinutes >= vigorousCadence
        }

        // MARK: Scoring

        /// The whole decomposition for one window, or nil when there is not enough
        /// to say. Nil arises for four separate reasons, all of them real: too few
        /// heart-rate samples, a lead-in spoiled by exercise, no curve fitted yet,
        /// or a pace the curve has never seen.
        func reading(for window: Window) -> Reading? {
            guard let curve, let summary = summary(for: window) else { return nil }
            guard curve.canExplain(cadence: summary.cadence) else { return nil }

            let explained = curve.explained(atCadence: summary.cadence)
            let expected = curve.baseline(for: summary.cell) + explained

            return Reading(
                windowId: summary.windowId,
                observed: summary.heartRate,
                expected: expected,
                explainedByMovement: explained,
                residual: summary.heartRate - expected,
                cadence: summary.cadence,
                cadenceBin: summary.bin,
                sampleCount: summary.sampleCount,
                uncertainty: uncertainty(cadence: summary.cadence, sampleCount: summary.sampleCount, curve: curve)
            )
        }

        func reading(for session: Session) -> Reading? {
            guard let window = Window(session: session) else { return nil }
            return reading(for: window)
        }

        /// The number `EngineObservation.heartRateResidual` carries. Nil when there
        /// is not enough to say — never zero, which would read as "measured, and no
        /// difference".
        func residual(for session: Session) -> Double? {
            reading(for: session)?.residual
        }

        /// Steps per minute across the session, for the movement context that
        /// travels with the residual.
        func cadence(for session: Session) -> Double? {
            guard let window = Window(session: session) else { return nil }
            return summary(for: window)?.cadence
        }

        /// How wide the error bar is, in bpm.
        ///
        /// The term that matters is the cadence one, and it points the opposite way
        /// from intuition. Wrist optical heart rate is *least* accurate while
        /// moving: a couple of beats out at rest, ten or more once the sensor is
        /// sliding against a moving wrist. So the high-cadence corrections — the
        /// ones doing the most arithmetic, subtracting the largest numbers — are
        /// also the least trustworthy. Widening here rather than narrowing is the
        /// only thing that stops a big correction from reading as a precise one.
        ///
        /// Three terms, added rather than combined in quadrature, because they are
        /// not independent and the conservative sum is the one worth being wrong in
        /// the direction of.
        private func uncertainty(cadence: Double, sampleCount: Int, curve: MovementCurve) -> Double {
            let ownScatter = curve.referenceSpread
            let motion = 1.5 + 0.06 * min(cadence, 180)
            let thinness = 4.0 / Double(max(sampleCount, 1)).squareRoot()
            return ownScatter + motion + thinness
        }
    }

    // MARK: - Simulator data


    // MARK: - Small statistics

    /// Kept private and local rather than reaching into `Statistics`, which is
    /// about ordinal comparisons between groups of ratings and shares no shape with
    /// any of this.

    /// Samples whose timestamp falls inside `[from, to]`. Binary search on the
    /// lower bound: a year of heart rate is tens of thousands of samples, and a fit
    /// scans it once per window.
    static func slice(_ samples: [Sample], from: Date, to: Date) -> ArraySlice<Sample> {
        guard !samples.isEmpty, to >= from else { return [] }
        var low = 0
        var high = samples.count
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].at < from { low = mid + 1 } else { high = mid }
        }
        var end = low
        while end < samples.count, samples[end].at <= to { end += 1 }
        return samples[low..<end]
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Median absolute deviation. The scale estimate that survives the motion
    /// artifacts a standard deviation would be dominated by.
    static func medianAbsoluteDeviation(_ values: [Double]) -> Double? {
        guard let centre = median(values) else { return nil }
        return median(values.map { abs($0 - centre) })
    }
}
