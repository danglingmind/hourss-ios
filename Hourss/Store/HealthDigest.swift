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
        /// Normalised effect size, used only for ranking.
        var strength: Double

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
        let ranked = candidates.sorted { $0.strength > $1.strength }
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

        let names = calendar.weekdaySymbols
        let highDay = names[(means.firstIndex { $0 == high }! + 1) % 7]
        let lowDay = names[(means.firstIndex { $0 == low }! + 1) % 7]

        return Fact(
            figure: difference(metric, high - low),
            sentence: "\(plural(lowDay)) run \(difference(metric, high - low)) \(metric.lowerDirection) than \(plural(highDay)).",
            group: metric.group,
            kind: .rhythm,
            mark: .weekdayRhythm(present.map { ($0 - low) / (high - low) }),
            strength: strength
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
            strength: strength
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
            // Ranked below rhythm and contrast: a trend is the least surprising of
            // the three, and the most likely to be measurement drift.
            strength: strength * 0.7
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
            // Deliberately last: it is a number, not a discovery.
            strength: 0.05
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
        case .hrv, .restingHeartRate, .respiratoryRate, .activeEnergy:
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
