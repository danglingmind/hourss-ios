import Foundation

/// Flattens the store's records into the rows the engine tests hypotheses over.
///
/// This is the only place that knows about both sides. `HourssStore` holds
/// sessions, reflections and health; `Engine` holds statistics and knows nothing
/// about either. Keeping the translation here is what lets the engine be tested
/// with hand-built rows and no store at all.
enum ObservationBuilder {

    /// Build one row per pattern-eligible session.
    ///
    /// Sessions that are still running, under five minutes, or over sixteen hours
    /// are excluded by `isEligibleForPatterns` — the spec's own validity rules.
    /// Everything surviving that becomes a row, **including unrated ones**: a row
    /// with `feeling == nil` still carries movement and health, so it can serve a
    /// physiological hypothesis even though no feeling hypothesis can use it.
    static func rows(
        sessions: [Session],
        reflections: [UUID: Reflection],
        activities: [Activity],
        healthByDay: [HealthMetric: [Date: Double]] = [:],
        residuals: [UUID: Physiology.Reading] = [:],
        workdays: Set<Int> = [2, 3, 4, 5, 6],
        calendar: Calendar = .current
    ) -> [EngineObservation] {
        let names = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0.name) })
        let categories = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0.category) })

        return sessions.compactMap { session in
            guard session.isEligibleForPatterns else { return nil }
            let day = calendar.startOfDay(for: session.startAt)

            // Health is a property of the day the session sits in. Only metrics
            // that actually recorded a value that day appear — an absent metric
            // must stay absent rather than arriving as a zero, which would read
            // as "slept none" instead of "no data".
            var dayHealth: [HealthMetric: Double] = [:]
            for (metric, byDay) in healthByDay {
                if let value = byDay[day] { dayHealth[metric] = value }
            }

            let reading = residuals[session.id]
            return EngineObservation(
                sessionId: session.id,
                day: day,
                startAt: session.startAt,
                durationMinutes: session.durationMinutes,
                activityName: names[session.activityId] ?? "Session",
                activityCategory: categories[session.activityId] ?? "",
                timeBucket: session.timeBucket,
                durationBucket: session.durationBucket,
                isWorkday: workdays.contains(calendar.component(.weekday, from: session.startAt)),
                feeling: reflections[session.id]?.feelingScore.map(Double.init),
                performance: reflections[session.id]?.performanceScore.map(Double.init),
                dayHealth: dayHealth,
                heartRateResidual: reading?.residual,
                cadence: reading?.cadence
            )
        }
    }
}
