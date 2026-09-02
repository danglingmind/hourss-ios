import Foundation

/// Derives observations from logged sessions.
///
/// This is a deliberately small stand-in for the real Personal Pattern Engine, but
/// it is a real computation rather than a lookup table: the averages, the session
/// counts and the session list on the detail screen all come from the same data,
/// so the demo cannot show a claim its own evidence contradicts.
///
/// Copy follows the spec's rules — name the activity, the direction and the
/// evidence, and never state a rule about the person.
enum InsightBuilder {

    private struct Group {
        var ratings: [Int] = []
        var sessionIds: [UUID] = []

        var mean: Double {
            ratings.isEmpty ? 0 : Double(ratings.reduce(0, +)) / Double(ratings.count)
        }
    }

    static func build(
        sessions: [Session],
        reflections: [UUID: Reflection],
        activities: [Activity],
        healthByDay: [HealthMetric: [Date: Double]] = [:]
    ) -> [Insight] {
        let names = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0.name) })
        let window = "past 6 weeks"

        /// Rated, pattern-eligible sessions only. Unrated sessions are genuinely
        /// unknown and must not be counted as neutral.
        let rated = sessions.compactMap { session -> (Session, Int)? in
            guard session.isEligibleForPatterns,
                  let feeling = reflections[session.id]?.feelingScore else { return nil }
            return (session, feeling)
        }

        func group(_ filter: (Session, Int) -> Bool) -> Group {
            var g = Group()
            for (session, feeling) in rated where filter(session, feeling) {
                g.ratings.append(feeling)
                g.sessionIds.append(session.id)
            }
            return g
        }

        /// Confidence rises with both the size of the gap and the amount of
        /// evidence behind it — a large gap from three sessions should not read as
        /// strongly as a smaller gap from thirty.
        func confidence(_ a: Group, _ b: Group) -> Int {
            let gap = abs(a.mean - b.mean)
            let volume = min(Double(min(a.ratings.count, b.ratings.count)), 12) / 12
            return Int(min(96, 42 + gap * 22 + volume * 30))
        }

        var results: [Insight] = []

        func add(
            _ type: InsightType,
            statement: String,
            caveat: String,
            experiment: String?,
            focus: Group,
            focusLabel: String,
            baseline: Group,
            baselineLabel: String,
            minimum: Int = 4
        ) {
            guard focus.ratings.count >= minimum, baseline.ratings.count >= minimum else { return }
            let score = confidence(focus, baseline)
            guard Confidence.band(score) != .internalOnly else { return }
            results.append(
                Insight(
                    id: UUID(),
                    type: type,
                    statement: statement,
                    evidence: .init(
                        comparisonLabel: focusLabel,
                        comparisonValue: focus.mean,
                        comparisonCount: focus.ratings.count,
                        baselineLabel: baselineLabel,
                        baselineValue: baseline.mean,
                        baselineCount: baseline.ratings.count,
                        windowDescription: window,
                        sessionIds: focus.sessionIds + baseline.sessionIds
                    ),
                    confidence: score,
                    status: .visible,
                    generatedAt: Date(),
                    caveat: caveat,
                    experiment: experiment
                )
            )
        }

        func isNamed(_ session: Session, _ name: String) -> Bool { names[session.activityId] == name }

        // 1 — Best time window.
        add(
            .bestTimeWindow,
            statement: "Your Deep work sessions have felt more energizing in the morning lately.",
            caveat: "Mornings may just be when your quieter hours land.",
            experiment: "Try holding one morning block this week and see whether it still feels different.",
            focus: group { s, _ in isNamed(s, "Deep work") && Calendar.current.component(.hour, from: s.startAt) < 11 },
            focusLabel: "Before 11am",
            baseline: group { s, _ in isNamed(s, "Deep work") && Calendar.current.component(.hour, from: s.startAt) >= 11 },
            baselineLabel: "After 11am"
        )

        // 2 — Draining time window.
        add(
            .drainingTimeWindow,
            statement: "Meetings after 3pm have tended to feel more draining.",
            caveat: "Late meetings may carry the day rather than cause it.",
            experiment: "Move one late meeting earlier next week and note how it lands.",
            focus: group { s, _ in isNamed(s, "Meetings") && Calendar.current.component(.hour, from: s.startAt) >= 15 },
            focusLabel: "After 3pm",
            baseline: group { s, _ in isNamed(s, "Meetings") && Calendar.current.component(.hour, from: s.startAt) < 15 },
            baselineLabel: "Before 3pm"
        )

        // 3 — Activity energizer.
        add(
            .activityEnergizer,
            statement: "Exercise is one of your more energizing activities.",
            caveat: "Fewer sessions than most — worth watching.",
            experiment: nil,
            focus: group { s, _ in isNamed(s, "Exercise") },
            focusLabel: "Exercise",
            baseline: group { s, _ in !isNamed(s, "Exercise") },
            baselineLabel: "Everything else",
            minimum: 3
        )

        // 4 — Activity drain.
        add(
            .activityDrain,
            statement: "Admin has landed below your usual feeling baseline recently.",
            caveat: "Admin is often short and scattered. That may matter too.",
            experiment: "Try grouping admin into one block and see whether it reads differently.",
            focus: group { s, _ in isNamed(s, "Admin") },
            focusLabel: "Admin",
            baseline: group { s, _ in !isNamed(s, "Admin") },
            baselineLabel: "Everything else"
        )

        // 6 — Duration sweet spot.
        add(
            .durationSweetSpot,
            statement: "Your 30–89 minute Deep work sessions have felt stronger than longer ones.",
            caveat: "Longer sessions may just be the harder work.",
            experiment: "Try ending one long block at the 80 minute mark this week.",
            focus: group { s, _ in isNamed(s, "Deep work") && s.durationBucket == .medium },
            focusLabel: "30–89 min",
            baseline: group { s, _ in isNamed(s, "Deep work") && (s.durationBucket == .long || s.durationBucket == .extended) },
            baselineLabel: "90 min or more"
        )

        // 8 — Workday / rest-day contrast.
        add(
            .workdayContrast,
            statement: "Social time has felt more energizing on non-workdays.",
            caveat: "Weekend and weekday plans are rarely the same thing.",
            experiment: nil,
            focus: group { s, _ in
                let weekday = Calendar.current.component(.weekday, from: s.startAt)
                return weekday == 1 || weekday == 7
            },
            focusLabel: "Non-workdays",
            baseline: group { s, _ in
                let weekday = Calendar.current.component(.weekday, from: s.startAt)
                return weekday != 1 && weekday != 7
            },
            baselineLabel: "Workdays"
        )

        // Health context. One association per metric, on the same shape as the
        // spec's sleep-context observation: split the person's rated sessions by
        // whether that day sat above or below *their own* median, and compare.
        //
        // Never against a population, never a reading of anyone's health — a
        // business rule forbids inferring a medical, psychological or causal
        // conclusion, so everything is phrased "on days when…" and carries a
        // caveat.
        var healthResults: [Insight] = []

        for metric in HealthMetric.allCases {
            guard let byDay = healthByDay[metric], !byDay.isEmpty else { continue }

            let calendar = Calendar.current
            let daysWithBoth = Set(rated.map { calendar.startOfDay(for: $0.0.startAt) })
                .filter { byDay[$0] != nil }

            // The spec's evidence bar: ≥8 days carrying both a value and a rated
            // session, and ≥5 sessions per side.
            guard daysWithBoth.count >= 8 else { continue }
            let values = daysWithBoth.compactMap { byDay[$0] }.sorted()
            guard !values.isEmpty else { continue }
            let median = values[values.count / 2]

            func group(above: Bool) -> Group {
                var g = Group()
                for (session, feeling) in rated {
                    let day = calendar.startOfDay(for: session.startAt)
                    guard let value = byDay[day] else { continue }
                    guard (value >= median) == above else { continue }
                    g.ratings.append(feeling)
                    g.sessionIds.append(session.id)
                }
                return g
            }

            let higher = group(above: true)
            let lower = group(above: false)
            guard higher.ratings.count >= 5, lower.ratings.count >= 5 else { continue }

            // Name whichever side actually reads better, so the sentence states
            // the direction the evidence supports rather than a fixed one.
            let higherIsBetter = higher.mean >= lower.mean
            let phrase = higherIsBetter ? metric.higherPhrase : "\(metric.higherPhrase.hasPrefix("when") ? "when" : "after") the opposite"
            let statement = higherIsBetter
                ? "On days \(metric.higherPhrase), your sessions have felt better."
                : "On days \(metric.lowerPhrase.hasPrefix("when") || metric.lowerPhrase.hasPrefix("after") ? metric.lowerPhrase : "when \(metric.lowerPhrase)"), your sessions have felt better."
            _ = phrase

            let before = results.count
            add(
                metric == .sleepHours ? .sleepContext : .bodyContext,
                statement: statement,
                caveat: metric.caveat,
                experiment: nil,
                focus: higherIsBetter ? higher : lower,
                focusLabel: higherIsBetter ? metric.highLabel : metric.lowLabel,
                baseline: higherIsBetter ? lower : higher,
                baselineLabel: higherIsBetter ? metric.lowLabel : metric.highLabel,
                minimum: 5
            )
            if results.count > before {
                healthResults.append(results.removeLast())
            }
        }

        // Keep the feed sparse: the strongest two body observations, plus sleep if
        // it qualified. A wall of biometric claims is exactly the dashboard the
        // product is not.
        let sleepResult = healthResults.filter { $0.type == .sleepContext }
        let bodyResults = healthResults
            .filter { $0.type == .bodyContext }
            .sorted { $0.confidence > $1.confidence }
            .prefix(2)
        results.append(contentsOf: sleepResult)
        results.append(contentsOf: bodyResults)

        return results.sorted { $0.confidence > $1.confidence }
    }
}
