import Foundation
import Testing
@testable import Hourss

/// The registry and the correction, checked against properties rather than
/// against the numbers they happen to produce today.
///
/// Most of these assert an *absence*: that no id collides, that no row lands on
/// both sides of a question, that an interval containing zero can never reach a
/// visible band, that a person with no pattern gets no sentence. A pattern engine
/// fails by speaking, not by staying quiet, so the tests are mostly about silence.
@Suite("Hypothesis registry and false-discovery correction")
struct RegistryTests {

    // MARK: - Cohort bridge

    /// A cohort person, as the engine sees them.
    ///
    /// Lives here rather than in the cohort because it is a fact about engine v2's
    /// input shape, not about the people: the generator predates it and should not
    /// have to know it exists.
    static func observations(for person: SyntheticCohort.Person) -> [EngineObservation] {
        let calendar = Calendar.current
        let names = Dictionary(uniqueKeysWithValues: person.activities.map { ($0.id, $0) })
        let health = person.healthByDay
        // Profile's default working week. The cohort has no profile, so the
        // default is the only honest reading of its weekdays.
        let workdays: Set<Int> = [2, 3, 4, 5, 6]

        return person.sessions.compactMap { session -> EngineObservation? in
            guard session.isEligibleForPatterns, let activity = names[session.activityId] else { return nil }
            let day = calendar.startOfDay(for: session.startAt)
            let reflection = person.reflections[session.id]

            var dayHealth: [HealthMetric: Double] = [:]
            for (metric, byDay) in health {
                if let value = byDay[day] { dayHealth[metric] = value }
            }

            return EngineObservation(
                sessionId: session.id,
                day: day,
                startAt: session.startAt,
                durationMinutes: session.durationMinutes,
                activityName: activity.name,
                activityCategory: activity.category,
                timeBucket: session.timeBucket,
                durationBucket: session.durationBucket,
                isWorkday: workdays.contains(calendar.component(.weekday, from: session.startAt)),
                feeling: reflection?.feelingScore.map(Double.init),
                performance: reflection?.performanceScore.map(Double.init),
                dayHealth: dayHealth,
                heartRateResidual: nil,
                cadence: nil
            )
        }
    }

    /// The window a cohort person's data actually covers, so the engine is never
    /// handed a window claim wider than the data behind it.
    static func input(for person: SyntheticCohort.Person) -> EngineInput {
        let rows = observations(for: person)
        let days = Set(rows.map(\.day))
        let span = (days.min().map { Int((days.max()! .timeIntervalSince($0)) / 86_400) + 1 }) ?? 0
        return EngineInput(observations: rows, windowDays: max(1, span))
    }

    // MARK: - Fixtures for the correction

    /// A finding with a chosen p-value and nothing else that matters.
    ///
    /// Benjamini–Hochberg reads exactly one number off each finding, so everything
    /// else is filler. Filling it with a comparison clear of zero keeps the
    /// fixtures usable in the reportability assertions too.
    static func finding(
        id: String,
        p: Double,
        low: Double = 0.30,
        high: Double = 0.70,
        days: Int = 20
    ) -> Finding {
        Finding(
            hypothesis: Hypothesis(
                id: id, type: .bestTimeWindow, outcome: .feeling,
                focusLabel: "Focus", baselineLabel: "Baseline",
                focus: { _ in true }, baseline: { _ in false },
                phrase: { _ in "" }, caveat: "", experiment: nil
            ),
            comparison: Statistics.Comparison(
                delta: (low + high) / 2, low: low, high: high,
                focusCount: 40, baselineCount: 40,
                focusDays: days, baselineDays: days,
                pValue: p
            ),
            focusSessionIds: [], baselineSessionIds: [],
            focusCoverage: 0.8, baselineCoverage: 0.8,
            survivesCorrection: nil,
            windowDays: 42
        )
    }

    static func survivors(_ findings: [Finding], q: Double = Engine.falseDiscoveryRate) -> Set<String> {
        Set(Engine.applyingCorrection(to: findings, q: q)
            .filter { $0.survivesCorrection == true }
            .map(\.hypothesis.id))
    }

    // MARK: - The registry

    @Test("Every hypothesis id is unique")
    func idsAreUnique() {
        for person in SyntheticCohort.everyone {
            let ids = HypothesisRegistry.hypotheses(for: Self.observations(for: person)).map(\.id)
            #expect(ids.count == Set(ids).count, Comment(rawValue:
                "\(person.name): duplicate ids among \(ids.count) hypotheses — " +
                "\(Dictionary(grouping: ids, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted())"))
        }
    }

    @Test("No observation lands on both sides of the same question")
    func sidesAreDisjoint() {
        for person in SyntheticCohort.everyone {
            let rows = Self.observations(for: person)
            for hypothesis in HypothesisRegistry.hypotheses(for: rows) {
                let overlap = rows.filter { hypothesis.focus($0) && hypothesis.baseline($0) }
                #expect(overlap.isEmpty, Comment(rawValue:
                    "\(person.name): \(hypothesis.id) puts \(overlap.count) sessions on both sides"))
            }
        }
    }

    @Test("The registry covers what the old engine covered, and generates the rest")
    func coversTheOldEngine() {
        let rows = Self.observations(for: SyntheticCohort.afternoonSlump)
        let ids = Set(HypothesisRegistry.hypotheses(for: rows).map(\.id))

        for bucket in TimeBucket.allCases {
            #expect(ids.contains("time.\(bucket.rawValue).vs.rest.feeling"),
                    "missing a time window hypothesis")
        }
        for bucket in DurationBucket.allCases {
            #expect(ids.contains("duration.\(bucket.rawValue).vs.rest.feeling"),
                    "missing a duration hypothesis")
        }
        #expect(ids.contains("workday.non.vs.work.feeling"), "missing the workday contrast")

        // Generated from the data, not written down: one per activity actually
        // logged, one per metric actually present.
        for name in Set(rows.map(\.activityName)) {
            #expect(ids.contains("activity.\(HypothesisRegistry.slug(name)).vs.rest.feeling"),
                    Comment(rawValue: "no hypothesis for logged activity \(name)"))
        }
        for metric in Set(rows.flatMap(\.dayHealth.keys)) {
            #expect(ids.contains("health.\(metric.rawValue).higher.vs.lower.feeling"),
                    Comment(rawValue: "no hypothesis for present metric \(metric.rawValue)"))
        }
    }

    @Test("Ids are stable across two runs on the same data")
    func idsAreStable() {
        let first = Engine.run(Self.input(for: SyntheticCohort.afternoonSlump))
        let second = Engine.run(Self.input(for: SyntheticCohort.afternoonSlump))
        #expect(first.map(\.id) == second.map(\.id),
                "insight identity moved between two runs on identical data")
        #expect(first.map(\.statement) == second.map(\.statement),
                "phrasing moved between two runs on identical data")

        // And identity is a function of the question alone, so it survives the
        // data changing underneath it.
        #expect(Engine.identity(of: "time.afternoon.vs.rest.feeling")
                == Engine.identity(of: "time.afternoon.vs.rest.feeling"))
        #expect(Engine.identity(of: "time.afternoon.vs.rest.feeling")
                != Engine.identity(of: "time.morning.vs.rest.feeling"))
    }

    // MARK: - Benjamini–Hochberg

    @Test("Hand-computed example: exactly the first four survive")
    func stepUpByHand() {
        // m = 5, Q = 0.10, so thresholds are 0.02, 0.04, 0.06, 0.08, 0.10.
        //   0.001 ≤ 0.02  ✓
        //   0.008 ≤ 0.04  ✓
        //   0.030 ≤ 0.06  ✓
        //   0.070 ≤ 0.08  ✓   ← largest k
        //   0.200 ≤ 0.10  ✗
        let ps = ["a": 0.001, "b": 0.008, "c": 0.030, "d": 0.070, "e": 0.200]
        let survived = Self.survivors(ps.map { Self.finding(id: $0.key, p: $0.value) })
        #expect(survived == ["a", "b", "c", "d"], Comment(rawValue: "survived: \(survived.sorted())"))
    }

    @Test("Step-up rescues a rank that failed its own threshold")
    func stepUpIsNotPerHypothesis() {
        // m = 3, Q = 0.10, thresholds 0.0333, 0.0667, 0.10.
        //   0.001 ≤ 0.0333 ✓
        //   0.090 ≤ 0.0667 ✗   ← fails alone
        //   0.095 ≤ 0.10   ✓   ← largest k, so everything below it survives
        let survived = Self.survivors([
            Self.finding(id: "a", p: 0.001),
            Self.finding(id: "b", p: 0.090),
            Self.finding(id: "c", p: 0.095),
        ])
        #expect(survived == ["a", "b", "c"], Comment(rawValue: "survived: \(survived.sorted())"))
    }

    @Test("With one hypothesis the correction changes nothing")
    func singleHypothesisIsUncorrected() {
        // m = 1 makes the only threshold Q itself, so BH reduces to the
        // uncorrected decision — which is the point: correcting a single test
        // should cost nothing.
        #expect(Self.survivors([Self.finding(id: "only", p: 0.09)]) == ["only"])
        #expect(Self.survivors([Self.finding(id: "only", p: 0.11)]).isEmpty)
        #expect(Engine.applyingCorrection(to: []).isEmpty)
    }

    @Test("An untested hypothesis does not inflate m")
    func untestedHypothesesAreNotCounted() {
        // Two tested hypotheses at 0.040 and 0.045. Against m = 2 the thresholds
        // are 0.05 and 0.10 and both survive.
        let tested = [Self.finding(id: "a", p: 0.040), Self.finding(id: "b", p: 0.045)]
        #expect(Self.survivors(tested) == ["a", "b"])

        // Had three skipped hypotheses been counted anyway, m = 5 would have made
        // the thresholds 0.02 and 0.04 and lost both. Correcting for tests nobody
        // ran is not conservative, it is wrong.
        let inflated = tested + (0..<3).map { Self.finding(id: "skipped\($0)", p: 0.9) }
        #expect(Self.survivors(inflated).isEmpty,
                "the inflated arrangement should lose both — otherwise this test proves nothing")
    }

    @Test("Only hypotheses with enough days on both sides are ever tested")
    func thinSplitsAreSkipped() {
        let person = SyntheticCohort.shortHistory
        let rows = Self.observations(for: person)
        let asked = HypothesisRegistry.hypotheses(for: rows).count
        let tested = Engine.findings(for: Self.input(for: person))

        #expect(tested.count < asked, Comment(rawValue:
            "18 days should leave some of the \(asked) hypotheses untestable; \(tested.count) were tested"))
        for finding in tested {
            #expect(finding.comparison.focusDays >= finding.hypothesis.minimumDays,
                    Comment(rawValue: "\(finding.hypothesis.id) tested on \(finding.comparison.focusDays) focus days"))
            #expect(finding.comparison.baselineDays >= finding.hypothesis.minimumDays,
                    Comment(rawValue: "\(finding.hypothesis.id) tested on \(finding.comparison.baselineDays) baseline days"))
        }
    }

    // MARK: - The interval governs everything

    @Test("An interval spanning zero can never produce a visible band")
    func spanningZeroIsNeverVisible() {
        // Swept rather than sampled: no combination of a wide interval, a narrow
        // one, or a large point estimate may push a spanning comparison over the
        // visible floor.
        for low in stride(from: -1.0, through: -0.001, by: 0.05) {
            for high in stride(from: 0.001, through: 1.0, by: 0.05) {
                let comparison = Statistics.Comparison(
                    delta: (low + high) / 2, low: low, high: high,
                    focusCount: 500, baselineCount: 500,
                    focusDays: 200, baselineDays: 200, pValue: 0.0001
                )
                #expect(comparison.spansZero)
                #expect(Confidence.band(Engine.confidence(comparison)) == .internalOnly,
                        Comment(rawValue: "[\(low), \(high)] scored \(Engine.confidence(comparison))"))
            }
        }
    }

    @Test("An interval reaching into the negligible band cannot produce a visible band")
    func negligibleEdgeIsNeverVisible() {
        // Clear of zero, and a point estimate Cliff would call medium — but the
        // data is equally consistent with an effect of 0.05, which is nothing.
        let marginal = Statistics.Comparison(
            delta: -0.331, low: -0.487, high: -0.05,
            focusCount: 17, baselineCount: 200,
            focusDays: 17, baselineDays: 86, pValue: 0.001
        )
        #expect(!marginal.spansZero)
        #expect(marginal.magnitude != .negligible, "the point estimate alone would have passed")
        #expect(Confidence.band(Engine.confidence(marginal)) == .internalOnly,
                "an interval reaching into the negligible band surfaced anyway")

        // The same interval pushed clear of that band does surface.
        let clear = Statistics.Comparison(
            delta: -0.331, low: -0.487, high: -0.20,
            focusCount: 17, baselineCount: 200,
            focusDays: 17, baselineDays: 86, pValue: 0.001
        )
        #expect(Confidence.band(Engine.confidence(clear)) != .internalOnly)
    }

    @Test("Precision about nothing is not confidence")
    func perfectPrecisionAtZeroIsNotVisible() {
        // The tightest interval there is, around exactly no effect. Anything
        // reading precision before checking where the interval sits would rank
        // this first of everything.
        let nothing = Statistics.Comparison(
            delta: 0, low: 0, high: 0,
            focusCount: 400, baselineCount: 400,
            focusDays: 90, baselineDays: 90, pValue: 0.0005
        )
        #expect(Confidence.band(Engine.confidence(nothing)) == .internalOnly,
                "a zero-width interval at zero scored as a pattern")

        // And the other end: too few days to bootstrap at all returns the widest
        // possible interval, which must read as "not yet" rather than as certainty
        // about a large effect.
        let unbootstrappable = Statistics.Comparison(
            delta: 0.9, low: -1, high: 1,
            focusCount: 6, baselineCount: 6,
            focusDays: 3, baselineDays: 3, pValue: 1
        )
        #expect(Confidence.band(Engine.confidence(unbootstrappable)) == .internalOnly)
    }

    @Test("A spanning comparison is unreportable even if the correction passes it")
    func spanningZeroIsNeverReportable() {
        var finding = Self.finding(id: "spanning", p: 0.0001, low: -0.4, high: 0.9)
        finding.survivesCorrection = true
        #expect(!finding.isReportable, "a claim survived correction with zero inside its interval")
    }

    @Test("Confidence rises with separation and with precision, and not with volume")
    func confidenceTracksTheInterval() {
        func score(_ low: Double, _ high: Double, focus: Int = 40) -> Int {
            Engine.confidence(.init(delta: (low + high) / 2, low: low, high: high,
                                    focusCount: focus, baselineCount: focus,
                                    focusDays: focus, baselineDays: focus, pValue: 0.01))
        }
        #expect(score(0.40, 0.60) > score(0.05, 0.60), "further from zero should not score lower")
        #expect(score(0.40, 0.60) > score(0.40, 0.95), "a tighter interval should not score lower")
        #expect(score(0.30, 0.50, focus: 8) == score(0.30, 0.50, focus: 800),
                "session count reached the number by a route other than the interval")
        #expect(Engine.confidence(.init(delta: 0.9, low: 0.85, high: 0.95,
                                        focusCount: 40, baselineCount: 40,
                                        focusDays: 20, baselineDays: 20, pValue: 0.001)) <= 100)
    }

    // MARK: - Honest windows

    @Test("The window description reports the real span")
    func windowDescriptionIsHonest() {
        #expect(Engine.describe(windowDays: 18) == "past 18 days")
        #expect(Engine.describe(windowDays: 42) == "past 6 weeks")
        #expect(Engine.describe(windowDays: 90) == "past 3 months")

        // Eighteen days of data must not describe itself as six weeks, which is
        // exactly what the old engine printed.
        let person = SyntheticCohort.shortHistory
        let rows = Self.observations(for: person)
        let span = Set(rows.map(\.day))
        let actual = Int(span.max()!.timeIntervalSince(span.min()!) / 86_400) + 1

        // The caller asks for six weeks; the data has less, and the finding says so.
        for finding in Engine.findings(for: EngineInput(observations: rows, windowDays: 42)) {
            #expect(finding.windowDays <= actual, Comment(rawValue:
                "\(finding.hypothesis.id) claims \(finding.windowDays) days over \(actual) of data"))
            #expect(Engine.describe(windowDays: finding.windowDays) != "past 6 weeks",
                    "an 18-day history described itself as six weeks")
        }
    }

    // MARK: - Against the answer key

    @Test("Finds the real afternoon slump")
    func findsTheSlump() {
        let found = Engine.run(Self.input(for: SyntheticCohort.afternoonSlump))
        let timing = found.filter { $0.type == .bestTimeWindow || $0.type == .drainingTimeWindow }
        #expect(!timing.isEmpty, Comment(rawValue:
            "a planted 1.2-point slump was missed; found \(found.map(\.type.rawValue))"))
        #expect(timing.contains {
            $0.statement.contains("afternoon") || $0.statement.contains("morning")
        }, Comment(rawValue: "found timing claims about the wrong hours: \(timing.map(\.statement))"))
    }

    @Test("Says nothing about a person with no pattern")
    func staysQuietOnNoise() {
        let found = Engine.run(Self.input(for: SyntheticCohort.flatline))
        #expect(found.isEmpty, Comment(rawValue:
            "noise produced \(found.count) claims: " +
            found.map { "\($0.type.rawValue)@\($0.confidence)" }.joined(separator: ", ")))
    }

    @Test("Says 'not yet' when a real effect has too little evidence")
    func staysQuietOnThinEvidence() {
        let found = Engine.run(Self.input(for: SyntheticCohort.shortHistory))
        #expect(found.isEmpty, Comment(rawValue:
            "thin evidence produced \(found.count) claims: " +
            found.map { "\($0.type.rawValue)@\($0.confidence)" }.joined(separator: ", ")))
    }

    @Test("Every surviving claim carries evidence that matches it")
    func evidenceMatchesTheClaim() {
        for person in SyntheticCohort.everyone {
            for insight in Engine.run(Self.input(for: person)) {
                #expect(insight.band != .internalOnly, Comment(rawValue:
                    "\(person.name): \(insight.type.rawValue) surfaced at \(insight.confidence)"))
                #expect(insight.evidence.comparisonCount > 0, "empty comparison group")
                #expect(insight.evidence.baselineCount > 0, "empty baseline group")
                #expect(insight.evidence.sessionIds.count ==
                        insight.evidence.comparisonCount + insight.evidence.baselineCount,
                        Comment(rawValue: "\(person.name): \(insight.type.rawValue) cites the wrong sessions"))
                #expect(!insight.caveat.isEmpty, "a claim shipped without its limit")
            }
        }
    }

    @Test("Uneven rating coverage is named in the caveat")
    func unevenCoverageIsDisclosed() {
        for person in SyntheticCohort.everyone {
            let corrected = Engine.applyingCorrection(to: Engine.findings(for: Self.input(for: person)))
            let uneven = corrected.filter { $0.isReportable && $0.hasUnevenCoverage }
            let ids = Set(uneven.map { Engine.identity(of: $0.hypothesis.id) })
            guard !ids.isEmpty else { continue }
            for insight in Engine.run(Self.input(for: person)) where ids.contains(insight.id) {
                #expect(insight.caveat.contains("rated at different rates"), Comment(rawValue:
                    "\(person.name): \(insight.type.rawValue) hides its uneven coverage"))
            }
        }
    }

    @Test("Copy makes no causal, medical or population claim")
    func copyStaysWithinItsRules() {
        // Not a substitute for reading the strings, but it catches the words that
        // turn an association into a diagnosis or a comparison with other people.
        let forbidden = ["because", "causes", "caused", "due to", "leads to", "makes you",
                         "healthy", "unhealthy", "average person", "most people", "than others",
                         "you should", "you always", "you never", "diagnos", "risk of"]
        for person in SyntheticCohort.everyone {
            for insight in Engine.run(Self.input(for: person)) {
                let text = (insight.statement + " " + insight.caveat + " " + (insight.experiment ?? ""))
                    .lowercased()
                for word in forbidden {
                    #expect(!text.contains(word), Comment(rawValue:
                        "\(person.name): '\(word)' in \(insight.statement) / \(insight.caveat)"))
                }
            }
            for insight in Engine.run(Self.input(for: person))
            where insight.type == .sleepContext || insight.type == .bodyContext {
                #expect(insight.statement.hasPrefix("On days "), Comment(rawValue:
                    "health claim not anchored on the day: \(insight.statement)"))
                #expect(!insight.caveat.isEmpty, "health claim without a caveat")
            }
        }
    }
    // MARK: - Confidence has no cliff

    private func comparison(edge: Double, width: Double) -> Statistics.Comparison {
        Statistics.Comparison(delta: edge + width / 2, low: edge, high: edge + width,
                              focusCount: 40, baselineCount: 60,
                              focusDays: 30, baselineDays: 45, pValue: 0.004)
    }

    /// A real observation in the cohort sat at a near edge of exactly 0.147, the
    /// negligible boundary, and the old formula refused below it and paid nine
    /// points above it. A resampling change would have flipped it between hidden
    /// and mid-strength.
    @Test("Confidence never jumps at the negligible boundary")
    func confidenceHasNoCliff() {
        var previous = Engine.confidence(comparison(edge: 0.01, width: 0.30))
        var step = 0.02
        while step <= 0.60 {
            let score = Engine.confidence(comparison(edge: step, width: 0.30))
            #expect(score - previous <= 3, Comment(rawValue:
                    "confidence jumped \(score - previous) points at a near edge of \(step)"))
            #expect(score >= previous, Comment(rawValue:
                    "confidence fell from \(previous) to \(score) as the effect grew"))
            previous = score
            step += 0.01
        }
    }

    @Test("A near edge deep in the negligible band is not shown")
    func negligibleEdgeStaysHidden() {
        let barely = comparison(edge: 0.03, width: 0.20)
        #expect(Confidence.band(Engine.confidence(barely)) == .internalOnly, Comment(rawValue:
                "an interval reaching almost to zero scored \(Engine.confidence(barely))"))
    }

    @Test("A large, tightly pinned effect scores near the top")
    func largeTightEffectScoresHigh() {
        let strong = comparison(edge: 0.55, width: 0.15)
        #expect(Engine.confidence(strong) >= 80, Comment(rawValue:
                "a large effect with a tight interval scored \(Engine.confidence(strong))"))
    }

    @Test("Volume alone cannot buy confidence")
    func volumeBuysNothing() {
        let few = Statistics.Comparison(delta: 0.40, low: 0.25, high: 0.55,
                                        focusCount: 8, baselineCount: 9,
                                        focusDays: 7, baselineDays: 8, pValue: 0.004)
        let many = Statistics.Comparison(delta: 0.40, low: 0.25, high: 0.55,
                                         focusCount: 800, baselineCount: 900,
                                         focusDays: 300, baselineDays: 350, pValue: 0.004)
        #expect(Engine.confidence(few) == Engine.confidence(many),
                "session count reached confidence other than by narrowing the interval")
    }

}
