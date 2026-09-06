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
enum Outcome: String {
    case feeling, performance, heartRateResidual

    /// Which direction counts as good, for phrasing. Residuals are deliberately
    /// undirected: a higher heart rate than movement explains is not "bad", and
    /// saying so would be a medical claim.
    var higherIsBetter: Bool? {
        switch self {
        case .feeling, .performance: true
        case .heartRateResidual: nil
        }
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
