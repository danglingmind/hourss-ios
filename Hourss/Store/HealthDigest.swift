import Foundation

/// What Hourss can already say about someone, before they have logged anything.
///
/// This is the onboarding proof beat: a year of the person's own Health history,
/// reduced to the three most striking things in it. Curation is the whole point —
/// a wall of numbers is the dashboard this product exists not to be, and three
/// surprising ones are a reason to keep going.
///
/// Every fact here is an association about that person against their own history.
/// Never a norm, never a target, never a verdict — the same rule the insight
/// engine works under.
struct HealthDigest {

    struct Fact: Identifiable {
        let id = UUID()
        /// The number that carries the fact, already formatted.
        var figure: String
        /// One sentence. Reads as an observation, not advice.
        var sentence: String
        var group: HealthGroup
        var kind: Kind
        var mark: Mark

        /// Which generator produced this. Three facts of the same shape read as one
        /// fact repeated, however different their subjects.
        enum Kind { case rhythm, contrast, drift, scale }
        /// Normalised effect size. Orders facts of the same kind; it no longer
        /// decides which kind leads. See `surprise`.
        var strength: Double
        /// Which signal this is about, for the prior lookup.
        var metric: HealthMetric
        /// Whether the fact went up. A pattern that runs against what is ordinary
        /// is the interesting half of every prior in the table below.
        var raised: Bool

        enum Mark {
            /// Seven weekday means, normalised 0–1, Monday first.
            case weekdayRhythm([Double])
            /// Two labelled values on a shared scale.
            case comparison(highLabel: String, high: Double, lowLabel: String, low: Double)
            /// A figure standing alone.
            case none
        }
    }

    let facts: [Fact]
    /// Days of history the digest actually had to work with.
    let daysOfHistory: Int

    var isEmpty: Bool { facts.isEmpty }

    // MARK: - Building

    /// At least this many days on each side of any comparison, so no fact rests on
    /// a single Tuesday.
    private static let minimumDaysPerSide = 5

    // MARK: - Surprise

    // BOUNDARY — read before touching this table.
    //
    // These numbers encode what is *ordinarily* true of people, and they exist to
    // decide what to show first. Nothing derived from them may reach a figure, a
    // sentence, or any other string somebody reads: the "No population comparison"
    // rule means a person is only ever measured against their own history. Ranking
    // "your sleep is steadier at weekends than in the week" above the reverse is
    // legitimate, because the reverse is what almost everyone has. Saying so is
    // not.
    //
    // Separate from `Surprise.priors` on purpose. That table is about associations
    // with how a session felt; this one is about whether a signal has a shape of
    // its own. "More sleep goes with better days" and "sleep differs at weekends"
    // are different claims and would need different numbers even where they name
    // the same metric.
    private struct Prior {
        /// The direction it ordinarily runs in.
        let raised: Bool
        /// The share of people it holds for, in that direction.
        let share: Double
    }

    /// Keyed by metric and kind, since the same signal is banal in one shape and
    /// interesting in another: everyone knows they sleep in at weekends, and
    /// almost nobody knows their sleep has drifted since spring.
    private static let priors: [String: Prior] = [
        // The single most predictable thing an app can tell somebody.
        "sleepHours.contrast": Prior(raised: true, share: 0.88),
        "steps.contrast": Prior(raised: true, share: 0.70),
        "activeEnergy.contrast": Prior(raised: true, share: 0.68),
        "exerciseMinutes.contrast": Prior(raised: true, share: 0.66),
        "daylightMinutes.contrast": Prior(raised: true, share: 0.64),
        "restingHeartRate.contrast": Prior(raised: false, share: 0.62),
        "hrv.contrast": Prior(raised: true, share: 0.60),

        // A week having a shape is genuinely not common knowledge, but sleep is
        // the one people have noticed about themselves.
        "sleepHours.rhythm": Prior(raised: true, share: 0.55),

        // Totals are arithmetic, not discovery. Striking to read, and nobody is
        // surprised that a year contains a lot of hours.
        "sleepHours.scale": Prior(raised: true, share: 0.80),
        "steps.scale": Prior(raised: true, share: 0.78),

        // Drift is absent from this table on purpose. That a signal has moved
        // over months is not something people track about themselves, in any
        // direction, so every drift fact scores the neutral 0.5 and is carried by
        // its effect size alone.
    ]

    /// How ordinary this fact is, 0…1. Unknown pairs are neutral, so a signal
    /// nobody has folk expectations about is neither promoted nor punished.
    private static func expectedness(of fact: Fact) -> Double {
        guard let prior = priors["\(fact.metric.rawValue).\(kindKey(fact.kind))"] else { return 0.5 }
        // A fact running the other way is the same prior read from its
        // complement, so someone who sleeps *less* at weekends outranks the
        // ordinary case by the ratio of their surprise rather than by a bonus.
        return fact.raised == prior.raised ? prior.share : 1 - prior.share
    }

    private static func kindKey(_ kind: Fact.Kind) -> String {
        switch kind {
        case .rhythm: "rhythm"
        case .contrast: "contrast"
        case .drift: "drift"
        case .scale: "scale"
        }
    }

    /// Surprise in bits, modified by effect size within a bounded range.
    ///
    /// The effect term spans a factor of 1.5 while the prior spans about five, so
    /// size still orders two facts of the same kind — which is what it is good
    /// for — and can never lift a banal fact over a surprising one. That inversion
    /// is the whole reason this replaced ranking on effect size: sorting by
    /// magnitude guarantees leading with the most obvious true thing about
    /// somebody, because the obvious things are obvious *for* being large.
    static func surprise(of fact: Fact) -> Double {
        let bits = -log2(max(0.05, expectedness(of: fact)))
        let size = 1 + 0.5 * min(1, fact.strength / 0.35)
        return bits * size
    }

    static func build(from dailyValues: [HealthMetric: [Date: Double]]) -> HealthDigest {
        let allDays = Set(dailyValues.values.flatMap(\.keys))
        guard !allDays.isEmpty else { return HealthDigest(facts: [], daysOfHistory: 0) }

        var candidates: [Fact] = []
        for (metric, byDay) in dailyValues where byDay.count >= minimumDaysPerSide * 2 {
            candidates.append(contentsOf: [
                weekdayRhythm(metric, byDay),
                weekendContrast(metric, byDay),
                drift(metric, byDay),
                scale(metric, byDay),
            ].compactMap { $0 })
        }

        // Strongest first, but never the same shape twice and never the same
        // topic twice: three weekday rhythms about three metrics still reads as
        // one idea, and the screen has to feel like three discoveries.
        let ranked = candidates.sorted {
            let left = surprise(of: $0), right = surprise(of: $1)
            if left != right { return left > right }
            // Ties fall back to size and then to the metric, so two runs over one
            // history put the same fact first.
            if $0.strength != $1.strength { return $0.strength > $1.strength }
            return $0.metric.rawValue < $1.metric.rawValue
        }
        var chosen: [Fact] = []
        var usedGroups: Set<HealthGroup> = []
        var usedKinds: Set<Fact.Kind> = []

        for fact in ranked where chosen.count < 3 {
            guard !usedGroups.contains(fact.group), !usedKinds.contains(fact.kind) else { continue }
            chosen.append(fact)
            usedGroups.insert(fact.group)
            usedKinds.insert(fact.kind)
        }
        // If variety could not be had, fill the remainder on topic alone rather
        // than showing fewer than three.
        for fact in ranked where chosen.count < 3 {
            guard !usedGroups.contains(fact.group) else { continue }
            chosen.append(fact)
            usedGroups.insert(fact.group)
        }

        return HealthDigest(facts: chosen, daysOfHistory: allDays.count)
    }

    // MARK: - Candidate generators

    /// The widest gap between two weekdays. The most surprising of the four,
    /// because almost nobody knows their own week has a shape.
    private static func weekdayRhythm(_ metric: HealthMetric, _ byDay: [Date: Double]) -> Fact? {
        let calendar = Calendar.current
        var buckets: [Int: [Double]] = [:]
        for (day, value) in byDay {
            // 1=Sunday in Foundation; shift so Monday is 0.
            let weekday = (calendar.component(.weekday, from: day) + 5) % 7
            buckets[weekday, default: []].append(value)
        }

        let means = (0..<7).map { index -> Double? in
            guard let values = buckets[index], values.count >= 3 else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }
        let present = means.compactMap { $0 }
        guard present.count == 7, let high = present.max(), let low = present.min(), low > 0 else { return nil }

        let strength = (high - low) / low
        guard strength > 0.08 else { return nil }

        // Monday-first indices, so 5 and 6 are Saturday and Sunday.
        let highIndex = means.firstIndex { $0 == high }!
        let lowIndex = means.firstIndex { $0 == low }!

        // If the two extremes sit on opposite sides of the weekend, this is the
        // weekend contrast wearing a different hat — and the contrast generator
        // describes it better, using every day rather than the two furthest apart.
        //
        // Letting it through would also be a way around the prior: "your sleep
        // varies across the week" carries no folk expectation and would rank as a
        // discovery, while the same effect stated as a weekend contrast is the
        // most predictable thing this product can say.
        let highIsWeekend = highIndex >= 5
        let lowIsWeekend = lowIndex >= 5
        guard highIsWeekend == lowIsWeekend else { return nil }

        let names = calendar.weekdaySymbols
        let highDay = names[(highIndex + 1) % 7]
        let lowDay = names[(lowIndex + 1) % 7]

        return Fact(
            figure: difference(metric, high - low),
            sentence: "\(plural(lowDay)) run \(difference(metric, high - low)) \(metric.lowerDirection) than \(plural(highDay)).",
            group: metric.group,
            kind: .rhythm,
            mark: .weekdayRhythm(present.map { ($0 - low) / (high - low) }),
            strength: strength,
            metric: metric,
            // A spread across seven days has no direction of its own; the prior
            // for a rhythm turns on the metric alone.
            raised: true
        )
    }

    /// Weekends against the working week.
    private static func weekendContrast(_ metric: HealthMetric, _ byDay: [Date: Double]) -> Fact? {
        let calendar = Calendar.current
        var weekend: [Double] = []
        var weekdays: [Double] = []
        for (day, value) in byDay {
            let index = calendar.component(.weekday, from: day)
            if index == 1 || index == 7 { weekend.append(value) } else { weekdays.append(value) }
        }
        guard weekend.count >= minimumDaysPerSide, weekdays.count >= minimumDaysPerSide else { return nil }

        let weekendMean = weekend.reduce(0, +) / Double(weekend.count)
        let weekdayMean = weekdays.reduce(0, +) / Double(weekdays.count)
        guard weekdayMean > 0 else { return nil }

        let strength = abs(weekendMean - weekdayMean) / weekdayMean
        guard strength > 0.08 else { return nil }

        let higherAtWeekends = weekendMean > weekdayMean
        return Fact(
            figure: "\(Int((strength * 100).rounded()))%",
            sentence: "Your \(metric.plainName) reads \(Int((strength * 100).rounded()))% \(higherAtWeekends ? "higher" : "lower") at weekends.",
            group: metric.group,
            kind: .contrast,
            mark: .comparison(
                highLabel: higherAtWeekends ? "Weekends" : "Weekdays",
                high: max(weekendMean, weekdayMean),
                lowLabel: higherAtWeekends ? "Weekdays" : "Weekends",
                low: min(weekendMean, weekdayMean)
            ),
            strength: strength,
            metric: metric,
            raised: higherAtWeekends
        )
    }

    /// The recent half against the earlier half — what has been changing.
    private static func drift(_ metric: HealthMetric, _ byDay: [Date: Double]) -> Fact? {
        let sorted = byDay.sorted { $0.key < $1.key }
        guard sorted.count >= minimumDaysPerSide * 2 else { return nil }
        let midpoint = sorted.count / 2
        let earlier = sorted.prefix(midpoint).map(\.value)
        let recent = sorted.suffix(from: midpoint).map(\.value)

        let earlierMean = earlier.reduce(0, +) / Double(earlier.count)
        let recentMean = recent.reduce(0, +) / Double(recent.count)
        guard earlierMean > 0 else { return nil }

        let strength = abs(recentMean - earlierMean) / earlierMean
        guard strength > 0.10 else { return nil }

        return Fact(
            figure: difference(metric, abs(recentMean - earlierMean)),
            sentence: "Your \(metric.plainName) has been \(recentMean > earlierMean ? "running higher" : "easing down") lately.",
            group: metric.group,
            kind: .drift,
            mark: .comparison(
                highLabel: "Recently",
                high: recentMean,
                lowLabel: "Earlier",
                low: earlierMean
            ),
            // Damped a little: a trend is the most likely of the four to be
            // measurement drift rather than the person changing.
            strength: strength * 0.7,
            metric: metric,
            raised: recentMean > earlierMean
        )
    }

    /// Sheer accumulation. Never the most interesting fact, but it never fails to
    /// be available, which makes it the reliable third.
    private static func scale(_ metric: HealthMetric, _ byDay: [Date: Double]) -> Fact? {
        guard metric.isCumulative else { return nil }
        let total = byDay.values.reduce(0, +)
        guard total > 0 else { return nil }
        return Fact(
            figure: total >= 1000
                ? total.formatted(.number.precision(.fractionLength(0)))
                : total.formatted(.number.precision(.fractionLength(0))),
            sentence: "\(metric.totalPhrase(total)) across \(byDay.count) days.",
            group: metric.group,
            kind: .scale,
            mark: .none,
            // A total is arithmetic rather than discovery, and its prior says so.
            strength: 0.05,
            metric: metric,
            raised: true
        )
    }

    // MARK: - Formatting

    private static func difference(_ metric: HealthMetric, _ value: Double) -> String {
        switch metric {
        case .sleepHours:
            let minutes = Int((value * 60).rounded())
            return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes) minutes"
        case .hrv, .restingHeartRate, .respiratoryRate:
            return "\(Int(value.rounded())) \(metric.shortUnit)"
        default:
            return "\(Int(value.rounded())) \(metric.shortUnit)"
        }
    }

    private static func plural(_ weekday: String) -> String { "\(weekday)s" }
}

extension HealthMetric {
    /// How the metric reads in a sentence about a person.
    var plainName: String {
        switch self {
        case .sleepHours: "sleep"
        case .hrv: "heart rate variability"
        case .restingHeartRate: "resting heart rate"
        // Never reached: heart rate is not a daily context metric and so never
        // reaches a digest. Present because the switch is exhaustive.
        case .heartRate: "heart rate"
        case .respiratoryRate: "breathing rate"
        case .workoutMinutes: "workout time"
        case .steps: "step count"
        case .activeEnergy: "active energy"
        case .exerciseMinutes: "exercise time"
        case .mindfulMinutes: "quiet time"
        case .daylightMinutes: "time outside"
        }
    }

    var shortUnit: String {
        switch self {
        case .sleepHours: "h"
        case .hrv: "ms"
        case .restingHeartRate, .respiratoryRate: "bpm"
        case .steps: "steps"
        case .activeEnergy: "kcal"
        default: "min"
        }
    }

    /// The direction word for the lower side of a weekday comparison.
    /// The word for the low side of a comparison. A duration is "shorter"; a rate
    /// or a variability reading is "lower", and a step count is "fewer".
    var lowerDirection: String {
        switch self {
        case .sleepHours, .workoutMinutes, .exerciseMinutes, .mindfulMinutes, .daylightMinutes:
            "shorter"
        case .steps:
            "fewer"
        case .hrv, .restingHeartRate, .respiratoryRate, .activeEnergy, .heartRate:
            "lower"
        }
    }

    func totalPhrase(_ total: Double) -> String {
        let rounded = Int(total.rounded())
        switch self {
        case .sleepHours: return "\(rounded) hours asleep"
        case .steps: return "\(rounded.formatted()) steps"
        case .activeEnergy: return "\(rounded.formatted()) kcal burned"
        case .workoutMinutes: return "\(rounded) minutes of workouts"
        case .exerciseMinutes: return "\(rounded) minutes of exercise"
        case .mindfulMinutes: return "\(rounded) minutes of quiet"
        case .daylightMinutes: return "\(rounded) minutes outside"
        default: return "\(rounded) \(shortUnit)"
        }
    }
}
