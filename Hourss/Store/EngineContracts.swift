import Foundation

/// The shapes engine v2 is assembled from.
///
/// The old engine hardcoded sixteen comparisons as sixteen blocks of code, so
/// adding a question meant editing the engine and every question carried its own
/// private idea of what counted as evidence. Here a question is *data*: a
/// `Hypothesis` value in a registry, tested by machinery that has no idea what it
/// is testing. Adding one is adding an array element.

// MARK: - The row

/// One logged session, flattened into everything a hypothesis might split on.
///
/// Built once per run. Hypotheses receive these and nothing else, which is what
/// keeps them declarative — a predicate over a row cannot accidentally reach into
/// the store or recompute health.
struct EngineObservation {
    let sessionId: UUID
    /// Start of the calendar day this session began in. The bootstrap clusters on
    /// this, so it must be a day boundary rather than the session's timestamp.
    let day: Date
    let startAt: Date
    let durationMinutes: Int
    let activityName: String
    let activityCategory: String
    let timeBucket: TimeBucket
    let durationBucket: DurationBucket
    let isWorkday: Bool

    /// Feeling, if the person rated it. Nil is unknown and must never become 3 —
    /// the whole scale is meaningless if absence is silently given a value.
    let feeling: Double?
    let performance: Double?

    /// Health for the day this session sits on, as daily values. Association
    /// hypotheses split on these; nothing here is per-session.
    let dayHealth: [HealthMetric: Double]

    /// Movement-adjusted heart-rate residual for this session's own window:
    /// observed minus what this person's cadence and hour predict. Nil when there
    /// were too few samples, or the lead-in was contaminated by recent exercise.
    /// Layer 3 fills this; nothing else may.
    let heartRateResidual: Double?
    /// Steps per minute across the window. Carried alongside the residual so a
    /// claim can say how much movement there was rather than only that it was
    /// accounted for.
    let cadence: Double?

    /// The measurement a hypothesis compares.
    func value(of outcome: Outcome) -> Double? {
        switch outcome {
        case .feeling: feeling
        case .performance: performance
        case .heartRateResidual: heartRateResidual
        }
    }
}

/// What is being compared. Kept small on purpose — every addition here is a new
/// thing the phrasing layer has to know how to say.
/// `Codable` because `Experiment` stores which measurement it is testing. The raw
/// values are therefore a persisted format: renaming a case rewrites the meaning of
/// experiments already on somebody's phone, so they are append-only from here.
enum Outcome: String, Codable, Sendable {
    case feeling, performance, heartRateResidual
}

// MARK: - Which way is better

/// Which direction counts as good, for one person, in one run.
///
/// **This used to be `Outcome.higherIsBetter`**, a constant on the enum that was
/// `nil` for `heartRateResidual` — because whether a heart rate above what
/// movement explains is a good sign is a medical opinion, and the app does not
/// have one. The `nil` was correct and it was also a dead end:
/// `Recommendations.build` drops anything whose direction is nil and
/// `ExperimentDesign.isEligible` requires `true`, so **no `physiology.*` finding
/// could ever become a recommendation or an experiment**, by construction. The
/// engine did its most expensive computation, published a sentence about it, and
/// then declined to use it for anything.
///
/// The app still has no medical opinion, and nothing here gives it one. What it
/// has instead is *this person's own ratings*, which can answer the question for
/// this person and nobody else: `HypothesisRegistry.residualCalibration` compares
/// how sessions felt on the high side of their own median residual against the
/// low side, and the sign of that difference is the direction. So direction stops
/// being a fact about the measurement and becomes a fact about the person,
/// resolved once per engine run from evidence that ran through the same gates as
/// every other claim.
///
/// **Nil until a calibration is confirmed**, which is where everybody starts and
/// where anyone with a sparse watch stays. That is the safety property, not a
/// default waiting to be improved: everything downstream inherits this direction,
/// so a wrong one makes every physiology claim wrong *in the same wrong direction
/// at once*. Confidently wrong is worse than quiet, so a lead directs nothing —
/// see `resolved(from:)`.
struct OutcomeDirection: Equatable, Sendable {

    /// Whether a residual above this person's own usual has gone with sessions
    /// they rated better. Nil means no confirmed calibration.
    let residualHigherIsBetter: Bool?

    /// No calibration: exactly what the static constant used to say, which is why
    /// it is the default on `Finding`. A path that forgets to resolve a direction
    /// therefore behaves as the app did before this existed, rather than guessing.
    static let uncalibrated = OutcomeDirection(residualHigherIsBetter: nil)

    func higherIsBetter(_ outcome: Outcome) -> Bool? {
        switch outcome {
        // Not resolved, and never will be. A rating *is* the person's answer to
        // which way is better, so asking the evidence which end of it is good
        // would be asking it to confirm a tautology.
        case .feeling, .performance: true
        case .heartRateResidual: residualHigherIsBetter
        }
    }

    /// The direction this run's findings support, or none.
    ///
    /// Three conditions, and each of them is load-bearing:
    ///
    /// - **The calibration was tested at all.** No finding for it means it never
    ///   cleared `minimumDays`, which is six distinct rated days on each side of
    ///   the person's own median residual. Silence, not a guess.
    /// - **It is `isReportable`** — interval clear of zero, a non-negligible
    ///   effect, enough days, *and* `survivesCorrection`. A lead is explicitly not
    ///   enough. A lead is a claim the app has decided not to make yet, and a claim
    ///   it will not make cannot be the premise of every claim it does make.
    /// - **The sign comes from the evidence**, never from the hypothesis. Two
    ///   people can calibrate in opposite directions off identical-looking data,
    ///   and that is the correct outcome rather than a bug.
    ///
    /// This can only run *after* `Engine.applyingCorrection`, because
    /// `isReportable` reads `survivesCorrection` and that is nil until it has. The
    /// correction is also where it is called from, for that reason.
    static func resolved(from findings: [Finding]) -> OutcomeDirection {
        guard let calibration = findings.first(where: {
            $0.hypothesis.id == HypothesisRegistry.residualCalibrationId
        }) else { return .uncalibrated }

        // **Reportable *and* visible.** `isReportable` alone is the bar the PRD
        // asked for, and it is the wrong one by exactly one condition: `Engine.run`
        // additionally drops anything whose confidence band is `.internalOnly`, and
        // a finding can clear `isReportable` and still land there — an interval
        // clear of zero whose near edge reaches into Cliff's negligible band.
        //
        // Under the looser bar a direction could be in force while the sentence it
        // rests on is nowhere on screen: a premise reorienting every physiology
        // claim this person sees, which they were never shown, and therefore cannot
        // disagree with, argue about, or hide. Everything else in this engine is
        // built to be arguable. This one claim would not have been, and it is the
        // one with the most resting on it.
        //
        // The PRD's item 7 says `isReportable`; this is the amendment, taken
        // deliberately and recorded there.
        guard calibration.isReportable,
              Confidence.band(Engine.confidence(calibration.comparison)) != .internalOnly
        else { return .uncalibrated }

        return OutcomeDirection(residualHigherIsBetter: calibration.comparison.delta > 0)
    }
}

// MARK: - The question

/// One question the engine knows how to ask, as data rather than code.
struct Hypothesis {
    /// Stable across runs and across recomputation.
    ///
    /// Insight identity derives from this, which is what lets saved and hidden
    /// state survive a rebuild. The old engine minted a fresh UUID every time it
    /// recomputed, so applying health context silently wiped everything the person
    /// had saved.
    let id: String
    let type: InsightType
    let outcome: Outcome

    /// Human labels for the two sides, used verbatim in the evidence line.
    let focusLabel: String
    let baselineLabel: String

    /// Which rows fall on each side. A row may match neither; it must not match
    /// both, and the registry test asserts that.
    let focus: (EngineObservation) -> Bool
    let baseline: (EngineObservation) -> Bool

    /// Distinct days required on each side before this is tested at all.
    ///
    /// Days, not sessions. Six sessions on one Tuesday are one day of evidence
    /// about Tuesdays, and counting them as six is the pseudo-replication that let
    /// eighteen days of noise produce four confident claims.
    var minimumDays: Int = 6

    /// Turns a result into the sentence shown. Receives the finding so a claim and
    /// its numbers cannot drift apart.
    let phrase: (Finding) -> String
    /// The limit on what this claim can mean, shown with it and never optional.
    let caveat: String
    var experiment: String?
}

// MARK: - The result

/// A hypothesis, tested. Carries enough to phrase it, rank it, and explain it.
struct Finding {
    let hypothesis: Hypothesis
    let comparison: Statistics.Comparison
    let focusSessionIds: [UUID]
    let baselineSessionIds: [UUID]

    /// The share of each side that carried a rating at all.
    ///
    /// When these differ materially the comparison is between differently-selected
    /// groups, not just different conditions — someone who stops rating sessions
    /// that go badly produces exactly that. Measured here so a caveat can say so.
    let focusCoverage: Double
    let baselineCoverage: Double

    /// Set by the correction step once every hypothesis in the run is known.
    /// Nil means the correction has not run yet.
    var survivesCorrection: Bool?

    /// Whether the claim holds when the sessions nobody rated are assumed to have
    /// gone badly for it.
    ///
    /// Nil when the check did not apply, which is the ordinary case: it only runs
    /// where the two sides were rated at materially different rates, because that
    /// is when the comparison is between differently-selected groups rather than
    /// merely different conditions. Someone who stops rating sessions that go
    /// badly produces exactly that, and the effect is a real distortion of the
    /// number rather than something a caveat repairs.
    var survivesMissingness: Bool?

    /// How much of the reported window this evidence actually spans, in days.
    /// The old engine printed "past 6 weeks" on eighteen days of data.
    let windowDays: Int

    /// Which way round "better" is for this person, in this run.
    ///
    /// Stamped by `Engine.applyingCorrection`, for the same reason
    /// `survivesCorrection` is set there: both are facts about the whole run that
    /// no single finding can know on its own. Carried on the finding rather than
    /// threaded as a parameter because `publishedType`, `isEligible` and the
    /// recommendation filter all need it and all already have a finding in hand —
    /// and because six call sites construct findings and then correct them, so a
    /// parameter would be six places to forget.
    ///
    /// Defaults to `.uncalibrated`, which is precisely the behaviour of the
    /// constant this replaced. A finding built by hand in a test, or by a path that
    /// never corrects, is undirected about residuals and `true` about ratings.
    var direction: OutcomeDirection = .uncalibrated

    /// Which direction counts as good for what this finding measures. The resolved
    /// value — nothing should read `Outcome` for this, because `Outcome` no longer
    /// knows.
    var higherIsBetter: Bool? { direction.higherIsBetter(hypothesis.outcome) }

    /// Whether the two sides were rated at materially different rates.
    var hasUnevenCoverage: Bool { abs(focusCoverage - baselineCoverage) > 0.15 }

    /// Everything that must hold before this is allowed to become an Insight.
    var isReportable: Bool {
        comparison.isReportable
            && comparison.focusDays >= hypothesis.minimumDays
            && comparison.baselineDays >= hypothesis.minimumDays
            && (survivesCorrection ?? false)
            // Nil passes: the check did not apply because coverage was even.
            && (survivesMissingness ?? true)
    }
}

// MARK: - Input

/// Everything one engine run reads. Assembled by the caller so the engine itself
/// touches no services and is trivially testable.
struct EngineInput {
    let observations: [EngineObservation]
    /// The window the caller intended. Reported honestly: if the data spans less,
    /// the evidence line says what it actually spans.
    let windowDays: Int
    let priorities: [Priority]
    let generatedAt: Date

    init(observations: [EngineObservation],
         windowDays: Int = 42,
         priorities: [Priority] = [],
         generatedAt: Date = Date()) {
        self.observations = observations
        self.windowDays = windowDays
        self.priorities = priorities
        self.generatedAt = generatedAt
    }
}
