import Foundation

/// A fortnight somebody can accept on their first day, out of Health history alone.
///
/// **The hole this fills.** A proposal needs a `Finding`, a `Finding` needs rated
/// sessions, and `Engine.findings` drops any hypothesis without
/// `Hypothesis.minimumDays` distinct rated days on *each* side. So the measured
/// paths — confirmed claims and leads — cannot speak at all until somebody has
/// logged and rated across the better part of a fortnight, while a year of their
/// Health history sits on the phone unread. That emptiness is the complaint this
/// whole feature exists to answer, and until now the feature answered it on day
/// twelve.
///
/// **What a starter is.** Two halves, and keeping them apart is the honesty of the
/// thing:
///
/// 1. A **premise from Health**, carried verbatim from `HealthDigest` — descriptive,
///    about a reading, claiming nothing. "Your sleep reads 11% higher at weekends."
/// 2. A **change** aimed at a registry hypothesis that *does not exist yet*. By the
///    time the fortnight closes it does exist, if they logged — and if they did not,
///    `ExperimentOutcome.read` already treats a hypothesis missing from the registry
///    as `.cannotTell` rather than as an error. That is why the measurement path
///    needs no change for any of this: settling looks the hypothesis up live, and
///    absence was already a first-class answer.
///
/// **The premise is not the reason for the change, and the copy has to say so.**
/// This is the one place a starter could go wrong. A Health sentence printed
/// directly above an instruction reads as a justification whatever its words are,
/// and the relationship it would be justifying is exactly the thing the fortnight
/// is going to test. So every starter premise ends on a second sentence naming what
/// has *not* been read — see `ExperimentCopy.starterPremise`. The Health reading is
/// there as evidence the app has their history, which is the whole argument for a
/// day-one proposal, and never as evidence for the change.
///
/// **No instruction about the body, ever.** The obvious starter for somebody who
/// ranked Sleep first is "go to bed earlier", and it is forbidden: that is advice
/// the data does not reach and the app does not give. Health-seeded starters are
/// *responsive scheduling* only — the reading cannot be moved, so what gets put
/// against it is the change. `ExperimentCopy.change` is where that line is drawn and
/// starters reuse it unchanged rather than writing a second set of instructions.
///
/// **No Health, no starter.** Covered under `starters(for:healthByDay:...)`.
enum ExperimentStarters {

    // MARK: - Shapes

    /// A registry family a starter can aim at.
    ///
    /// Five cases, which is every family that both survives
    /// `ExperimentDesign.experimentableTypes` and can be named before anything has
    /// been logged. `physiology` is absent because its outcome is undirected, and
    /// the draining mirrors are absent because adherence counts days *gained* on the
    /// focus side — the two filters `ExperimentDesign` documents at length.
    enum Shape: Hashable {
        case time(TimeBucket)
        case duration(DurationBucket)
        case activity(String)
        case workday
        case health(HealthMetric)
    }

    /// Everything a shape needs to become a `Proposal`, once a Health fact has been
    /// attached to it.
    struct Blueprint: Equatable {
        let shape: Shape
        /// The registry key this fortnight will be settled against.
        let hypothesisId: String
        let type: InsightType
        let outcome: Outcome
        let focusLabel: String
        let baselineLabel: String
        let caveat: String
        let change: String
        /// The sentence that says what has not been read yet.
        let unknown: String
    }

    // MARK: - Floors

    /// Days of history a metric needs before a starter will aim at it.
    ///
    /// The target hypothesis only joins the registry once the metric sits on days
    /// that also carry a rating, and the verdict then needs six such days inside the
    /// window. A metric Health happens to hold for four days of a year will not
    /// supply them, so a starter aimed at it would be a fortnight that could only
    /// ever come back "cannot tell" — the app spending somebody's two weeks on a
    /// question it already knew it could not answer.
    ///
    /// Set to the window length rather than picked: a metric recorded on fewer days
    /// than the window is long cannot be relied on to cover the window.
    static let metricMinimumDays = Experiment.defaultWindowDays

    // MARK: - Selection

    /// Which shapes serve a priority, in preference order.
    ///
    /// **Selection is by priority, as everywhere else in this feature**, and each
    /// priority's own shapes come from `Priority.insightTypes` — the same map
    /// `ExperimentDesign.proposals` and `Recommendations.build` walk. `sleep` gets
    /// the sleep association because `sleepContext` is what `sleep` asks for;
    /// `movement` and `calm` get body associations over their own `HealthGroup`'s
    /// metrics; `balance` gets the workday contrast; `focus` gets a time window;
    /// `energy` gets an activity, which is the one experimentable type in its list.
    ///
    /// **Why `energy` names an activity, and the arbitrariness in it.** Nothing in
    /// Health names an activity, so unlike the other five this starter's subject
    /// cannot be read off the history — it has to be chosen. The choice is the top of
    /// the person's own picker order, which is at least *their* order and not ours,
    /// and it carries no evidence whatsoever. That is the weakest of the six and it
    /// is also exactly what a starter is for: there is nothing to go on, so the app
    /// says so and offers a place to begin. The alternative considered and rejected
    /// was giving `energy` a duration starter instead, which would have been less
    /// arbitrary and would have served a priority other than the one it was filed
    /// under — a worse trade, because the whole selection rule is that a starter
    /// serves the focus area somebody ranked.
    ///
    /// **The generic tail.** Appended to every priority, and it fires when a
    /// priority's own shapes are unavailable — a `sleep` ranking with no sleep data
    /// in Health, a `calm` ranking with no mindful or daylight minutes. These are
    /// real: Health carries only what the person's devices record. Time and duration
    /// hypotheses are minted by the registry unconditionally, so they are the shapes
    /// that are always available, and a starter that serves the priority less
    /// exactly is better than a focus area that produces nothing at all — which is
    /// the promise onboarding cannot keep that this phase exists to stop making.
    /// Durations lead the tail so that `time(.morning)` stays available to `focus`
    /// however the priorities are ordered.
    static let genericShapes: [Shape] = [
        .duration(.medium), .duration(.long), .duration(.short), .duration(.extended),
        .time(.morning), .time(.midday), .time(.afternoon), .time(.evening),
    ]

    static func shapes(for priority: Priority, activities: [Activity]) -> [Shape] {
        let own: [Shape]
        switch priority {
        case .focus:
            own = [.time(.morning)]
        case .energy:
            // Nil rather than a fallback name: an activity nobody has is an
            // instruction nobody can follow, and the generic tail covers it.
            own = activities.first.map { [.activity($0.name)] } ?? []
        case .sleep:
            own = [.health(.sleepHours)]
        case .movement:
            // In the order a phone is most likely to hold them. Steps are recorded
            // by the handset alone; exercise and workout minutes need a watch.
            own = [.health(.steps), .health(.activeEnergy),
                   .health(.exerciseMinutes), .health(.workoutMinutes)]
        case .calm:
            // Quiet time first, because `Priority.calm.basis` is "What quiet time
            // sits next to". Daylight is the same `HealthGroup` and is the one most
            // phones actually record.
            own = [.health(.mindfulMinutes), .health(.daylightMinutes)]
        case .balance:
            own = [.workday]
        }
        return own + genericShapes
    }

    // MARK: - Building

    /// Starters for these priorities, in the person's own order.
    ///
    /// **What happens when Health is not connected, or is thin.** Nothing is
    /// offered. A starter's premise *is* a Health fact, so with no facts there is no
    /// premise, and the alternative — inventing a reason, or showing a change with
    /// no premise at all — would be either a claim or a bare instruction. Neither is
    /// something this app does, and the slot falls back to the evidence mark it
    /// showed before this file existed, which is honest about there being nothing
    /// yet. Thin history lands in the same place without a special case:
    /// `HealthDigest`'s generators need ten days of a metric and five on each side of
    /// any comparison, so a week-old phone produces an empty pool.
    ///
    /// - Parameter healthByDay: the store's own `healthByDay`, which is exactly what
    ///   `HealthDigest.pool` consumes. The pool is recomputed here rather than passed
    ///   in because its ranking is `HealthDigest`'s to decide, and a caller handing
    ///   over a re-sorted pool would silently change which fact a starter quotes.
    /// - Parameter activities: the person's picker order, so the activity a starter
    ///   names is one they can actually choose.
    /// - Parameter measured: hypothesis keys the engine already produced a finding
    ///   for. A starter stands down for those: once there is enough to read, the
    ///   measured path owns the question, and a starter claiming nothing is known
    ///   about something the engine has read six days of each side of would be the
    ///   app contradicting itself. It also stops the uglier case — asking somebody
    ///   to do more of a group that currently reads *worse*, which no measured
    ///   proposal would ever do because `isEligible` refuses it.
    /// - Parameter excluding: declines and everything already tested, as
    ///   `ExperimentDesign.proposals` takes them and for the same reason.
    static func starters(
        for priorities: [Priority],
        healthByDay: [HealthMetric: [Date: Double]],
        activities: [Activity] = [],
        measured: Set<String> = [],
        excluding: Set<String> = []
    ) -> [ExperimentDesign.Proposal] {
        build(priorities: priorities, skipping: [], healthByDay: healthByDay,
              activities: activities, measured: measured, excluding: excluding)
    }

    /// Real proposals, with starters filling only the priorities they left empty.
    ///
    /// **A real finding always beats a starter**, and the ordering is how that is
    /// enforced rather than a comparison somewhere: measured proposals keep their
    /// places at the front in the order `ExperimentDesign` put them in, and starters
    /// are appended behind all of them. Today shows `proposals.first`, so a person
    /// with one real lead for their third priority sees that lead and not a starter
    /// for their first — which is the right way round. A starter is what the app
    /// offers when it has nothing better, never instead of something better, and a
    /// lead for any priority is something better than a sentence that begins by
    /// admitting nothing has been read.
    ///
    /// A priority that already produced a measured proposal gets no starter at all,
    /// so the list never holds two offers for one focus area.
    static func completing(
        _ proposals: [ExperimentDesign.Proposal],
        priorities: [Priority],
        healthByDay: [HealthMetric: [Date: Double]],
        activities: [Activity] = [],
        measured: Set<String> = [],
        excluding: Set<String> = []
    ) -> [ExperimentDesign.Proposal] {
        let served = Set(proposals.map(\.priority))
        let taken = excluding.union(proposals.map(\.hypothesisId))
        return proposals + build(
            priorities: priorities, skipping: served, healthByDay: healthByDay,
            activities: activities, measured: measured, excluding: taken)
    }

    /// One starter per unserved priority, or none.
    ///
    /// `skipping` rather than a filtered priority list, because `priorityRank` has to
    /// be the rank in what the person actually ranked. A starter that reported itself
    /// as their first priority because the two above it were served elsewhere would
    /// be a lie about their own list.
    private static func build(
        priorities: [Priority],
        skipping served: Set<Priority>,
        healthByDay: [HealthMetric: [Date: Double]],
        activities: [Activity],
        measured: Set<String>,
        excluding: Set<String>
    ) -> [ExperimentDesign.Proposal] {
        // Nothing was said about what matters, so there is no area to work on and
        // this layer picks none on somebody's behalf. The same guard
        // `ExperimentDesign.proposals` opens with.
        guard !priorities.isEmpty else { return [] }

        let pool = HealthDigest.pool(from: healthByDay)
        // No Health, no premise, no starter. See the note on `starters`.
        guard !pool.isEmpty else { return [] }

        var out: [ExperimentDesign.Proposal] = []
        var used = excluding.union(measured)

        for (rank, priority) in priorities.enumerated() where !served.contains(priority) {
            let candidates = shapes(for: priority, activities: activities)
            for shape in candidates {
                guard isAvailable(shape, healthByDay: healthByDay),
                      let blueprint = blueprint(for: shape),
                      !used.contains(blueprint.hypothesisId),
                      let fact = fact(for: shape, in: pool)
                else { continue }
                used.insert(blueprint.hypothesisId)
                out.append(proposal(blueprint, from: fact, priority: priority, rank: rank))
                break
            }
        }
        return out
    }

    /// Whether the registry will mint this shape's hypothesis once they log.
    ///
    /// Time, duration and workday hypotheses are registered unconditionally, so they
    /// are always available. An activity shape names an activity that exists by
    /// construction. A health shape is the only one that can fail, and it fails for
    /// the reason `metricMinimumDays` records.
    static func isAvailable(_ shape: Shape,
                            healthByDay: [HealthMetric: [Date: Double]]) -> Bool {
        switch shape {
        case .time, .duration, .activity, .workday:
            return true
        case .health(let metric):
            return (healthByDay[metric]?.count ?? 0) >= metricMinimumDays
        }
    }

    // MARK: - Blueprints

    /// The registry as it stands with nothing logged.
    ///
    /// Nine hypotheses: four time windows, four durations and the workday contrast.
    /// Activity and health hypotheses are functions of the observations and so are
    /// absent, which is the whole premise of this file.
    ///
    /// **Why this is looked up rather than spelled out.** A starter's whole
    /// mechanism is that its `hypothesisId` is the key `ExperimentOutcome` will look
    /// the predicate up by a fortnight later. An id typed by hand here and drifting
    /// by one character from the registry's would not fail, break a test or log
    /// anything — it would settle every one of these experiments as "cannot tell",
    /// silently, in two weeks, on somebody else's phone. For the three families the
    /// registry can produce without data, taking the id from the registry itself
    /// removes that failure entirely. The other two are constructed, and
    /// `ExperimentStarterTests` pins each constructed id against the registry built
    /// from observations that do support it.
    /// Rebuilt per call rather than cached in a `static let`, because a `Hypothesis`
    /// carries two closures and so is not `Sendable` — a shared mutable global of
    /// them does not compile under strict concurrency, and it should not. Nine rows
    /// of two closures and some strings is not a cost worth working around.
    private static var registered: [Hypothesis] { HypothesisRegistry.hypotheses(for: []) }

    /// A shape, resolved into everything the proposal needs.
    ///
    /// Labels and caveats come from the registry or from `HealthMetric`, never from
    /// this file: the proposal and the hypothesis it will be settled against have to
    /// name the two sides the same way, or a settled card reads about a split the
    /// person was never offered.
    static func blueprint(for shape: Shape) -> Blueprint? {
        switch shape {
        case .time(let bucket):
            return fromRegistry(shape, type: .bestTimeWindow, focusLabel: bucket.label)

        case .duration(let bucket):
            return fromRegistry(shape, type: .durationSweetSpot, focusLabel: bucket.label)

        case .workday:
            return fromRegistry(shape, type: .workdayContrast, focusLabel: nil)

        case .activity(let name):
            // `HypothesisRegistry.slug` is the registry's own function, so the id is
            // whatever it will be for this name rather than whatever this file
            // thinks slugging means.
            return assemble(
                shape,
                id: "activity.\(HypothesisRegistry.slug(name)).vs.rest.\(Outcome.feeling.rawValue)",
                type: .activityEnergizer,
                outcome: .feeling,
                focusLabel: name,
                baselineLabel: "Everything else",
                caveat: "What you do and when you do it are hard to pull apart.",
                metric: nil)

        case .health(let metric):
            return assemble(
                shape,
                id: "health.\(metric.rawValue).higher.vs.lower.\(Outcome.feeling.rawValue)",
                // The registry's own rule, which is why it is repeated rather than
                // reinterpreted: sleep is its own insight type and every other body
                // signal shares one.
                type: metric == .sleepHours ? .sleepContext : .bodyContext,
                outcome: .feeling,
                focusLabel: metric.highLabel,
                baselineLabel: metric.lowLabel,
                caveat: metric.caveat,
                metric: metric)
        }
    }

    /// A blueprint for one of the nine hypotheses that exist before anything is
    /// logged, taking its id, labels and caveat from the registry row itself.
    private static func fromRegistry(_ shape: Shape,
                                     type: InsightType,
                                     focusLabel: String?) -> Blueprint? {
        guard let hypothesis = registered.first(where: {
            $0.type == type && (focusLabel == nil || $0.focusLabel == focusLabel)
        }) else { return nil }
        return assemble(shape,
                        id: hypothesis.id,
                        type: hypothesis.type,
                        outcome: hypothesis.outcome,
                        focusLabel: hypothesis.focusLabel,
                        baselineLabel: hypothesis.baselineLabel,
                        caveat: hypothesis.caveat,
                        metric: nil)
    }

    private static func assemble(_ shape: Shape,
                                 id: String,
                                 type: InsightType,
                                 outcome: Outcome,
                                 focusLabel: String,
                                 baselineLabel: String,
                                 caveat: String,
                                 metric: HealthMetric?) -> Blueprint? {
        // Nil where no honest change can be asked for. Unreachable for the five
        // shapes above — every one of them is a type `ExperimentCopy.change` has a
        // sentence for — and kept as a guard rather than a force so that adding a
        // sixth shape without writing its change produces no starter instead of a
        // crash.
        guard let change = ExperimentCopy.change(
            type: type, focusLabel: focusLabel, metric: metric) else { return nil }

        return Blueprint(
            shape: shape,
            hypothesisId: id,
            type: type,
            outcome: outcome,
            focusLabel: focusLabel,
            baselineLabel: baselineLabel,
            caveat: caveat,
            change: change,
            unknown: ExperimentCopy.starterUnknown(
                type: type, focusLabel: focusLabel,
                baselineLabel: baselineLabel, metric: metric))
    }

    // MARK: - The premise

    /// Which Health fact supplies the premise for a shape.
    ///
    /// Most surprising first in every arm, because that is the order `HealthDigest`
    /// already ranks its pool in and the ranking is its decision, not this file's.
    /// What varies is which subset is preferred:
    ///
    /// - A health shape prefers a fact about the **same metric**, so the premise and
    ///   the change are plainly about the same days. Failing that, the same
    ///   `HealthGroup`, then anything.
    /// - The workday shape prefers a **weekend contrast**, which is the one fact in
    ///   the pool that is actually about days off against working days.
    /// - Everything else takes the most surprising fact there is. For `focus` and
    ///   `energy` nothing in Health names a time of day or an activity, so there is
    ///   no apter fact to prefer and pretending otherwise would be the implied
    ///   relationship the second premise sentence exists to deny.
    ///
    /// Two starters in one run may quote the same Health sentence. Left alone
    /// deliberately: only one proposal is ever on screen, and spending the second-best
    /// fact to avoid a repetition nobody can see would mean the one card somebody
    /// does read quotes the weaker fact.
    static func fact(for shape: Shape, in pool: [HealthDigest.Fact]) -> HealthDigest.Fact? {
        switch shape {
        case .health(let metric):
            // Matched on `subject.key`, which for a Health fact is the metric's raw
            // value. `HealthDigest.pool` produces Health facts only — the record half
            // of the pool comes from `RecordFacts` and needs sessions, which is the
            // thing a starter does not have.
            return pool.first { $0.subject.key == metric.rawValue }
                ?? pool.first { $0.subject.healthGroup == metric.group }
                ?? pool.first
        case .workday:
            return pool.first { $0.kind == .contrast } ?? pool.first
        case .time, .duration, .activity:
            return pool.first
        }
    }

    /// A blueprint and a fact, as something somebody can accept.
    ///
    /// The three evidence fields are zero, and they are zero because nothing has
    /// been measured. They exist on `Proposal` so a lead can quote its shrunk
    /// estimate and its day count — see `ExperimentDesign.estimate` — and a starter
    /// has neither. Nothing renders them for any standing today; the guard against
    /// one starting to is `Standing.starter` itself, which is the thing a card would
    /// have to ignore in order to print a rating this app never took.
    static func proposal(_ blueprint: Blueprint,
                         from fact: HealthDigest.Fact,
                         priority: Priority,
                         rank: Int) -> ExperimentDesign.Proposal {
        ExperimentDesign.Proposal(
            hypothesisId: blueprint.hypothesisId,
            outcome: blueprint.outcome,
            type: blueprint.type,
            standing: .starter,
            focusLabel: blueprint.focusLabel,
            baselineLabel: blueprint.baselineLabel,
            premise: ExperimentCopy.starterPremise(fact.sentence, unknown: blueprint.unknown),
            change: blueprint.change,
            caveat: blueprint.caveat,
            priority: priority,
            priorityRank: rank,
            evidenceDays: 0,
            figure: 0,
            baselineFigure: 0
        )
    }
}
