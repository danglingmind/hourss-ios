import Foundation

/// How a person's sessions have felt across the hours of their day.
///
/// **What this is for, and the one thing it may never do.** `TimeBucket` has four
/// values and `morning` is six hours wide, so the engine cannot tell 06:00 from
/// 10:30 and cannot form the sentence "try 07:00" however much somebody has logged.
/// This reads the hours they *have* used against each other, so that an hour
/// between them can be named. `PRD-HOURS.md` §3.1.
///
/// It is not evidence. Nothing here survived a correction, nothing here carries an
/// interval, and no number from it may reach a sentence. What it may do is what
/// `Surprise.priors` and `Physiology.DayShape` already do: **decide which question
/// is worth putting in front of somebody.** The fortnight still answers it. That is
/// §4 of the PRD and it is the whole integrity argument for the feature.
///
/// **Why a smoother and not a model.** We are not predicting a rating. We are
/// ranking candidate hours by whether they are worth two weeks of somebody's
/// attention, which is a much weaker claim — weak enough that a closed-form kernel
/// over one person's own ratings supports it, where a point prediction would not.
/// Inspectable in the same way `Shrinkage`'s method of moments is inspectable: every
/// number here can be recomputed by hand from the rows that produced it.
///
/// **Support is the important output, not the estimate.** A smooth function will
/// return a number for 03:00 to somebody who has never been awake at 03:00, and the
/// number will look exactly like the ones that mean something. `support` is the
/// summed kernel mass of real observations near an hour, and an hour below
/// `minimumSupport` has no estimate at all — nil rather than a low score, as
/// `Physiology` refuses rather than guesses. `SyntheticCohort.extrapolator` exists
/// to fail the build if that erodes.
enum RatingShape {

    // MARK: - Shape

    /// One hour of one kind of day.
    struct Hour: Equatable {
        let hour: Int
        let isWorkday: Bool
        /// The smoothed rating at this hour, on the 1–5 scale the ratings use.
        let estimate: Double
        /// How much real evidence sits near this hour, in day-equivalents: a support
        /// of 1 means the weight of exactly one day logged exactly here.
        let support: Double
    }

    /// Every hour that earned an estimate, for both kinds of day.
    struct Shape: Equatable {
        let hours: [Hour]

        var isEmpty: Bool { hours.isEmpty }

        func hour(_ hour: Int, isWorkday: Bool) -> Hour? {
            hours.first { $0.hour == hour && $0.isWorkday == isWorkday }
        }

        /// The best-estimated hour of this kind of day, ignoring hours in `used`.
        ///
        /// Ties break on the earlier hour so two runs over one history choose the
        /// same one — the same total-order discipline `MovementCurve.dayShape` keeps,
        /// and for the same reason: a shape that reshuffled itself between runs would
        /// hand a different proposal to the same person on two launches.
        func best(isWorkday: Bool, excluding used: Set<Int> = []) -> Hour? {
            hours
                .filter { $0.isWorkday == isWorkday && !used.contains($0.hour) }
                .max { left, right in
                    if left.estimate != right.estimate { return left.estimate < right.estimate }
                    return left.hour > right.hour
                }
        }
    }

    // MARK: - Constants

    /// How far the kernel reaches, in hours.
    ///
    /// The standard deviation of a wrapped Gaussian over hour-of-day. At 1.5 an hour
    /// one step away keeps 80% of its weight, two steps 41%, four steps 3% — so a
    /// neighbouring hour informs an estimate strongly, the far side of a band weakly,
    /// and the other side of the day not at all.
    ///
    /// **Narrower refuses more and interpolates less; wider invents.** This is
    /// `PRD-HOURS.md` open decision 3, and the method for settling it is the one the
    /// document states: pick it from the cohort and record what it costs. 1.5 is the
    /// value at which `SyntheticCohort.interpolator` is recovered at 07:00 and
    /// `extrapolator` is still refused there, measured in `RatingShapeTests`.
    static let bandwidth: Double = 1.5

    /// How much evidence an hour needs before it is allowed an estimate, in
    /// day-equivalents.
    ///
    /// **This is the gate the whole feature's honesty rests on**, and the number
    /// cannot be derived — it answers "how much of somebody's own evidence is enough
    /// to be worth asking them about", which is a judgement. Stated here so it can be
    /// argued with rather than discovered inside a formula.
    ///
    /// Six is the engine's floor for *comparing* two sides, where the correction and
    /// the interval carry whatever uncertainty remains. Nothing here carries any, so
    /// this is deliberately stricter in what it means: six day-equivalents of kernel
    /// mass, not six days. An hour two steps from everything somebody logs needs
    /// fifteen days of that neighbour to reach it, and an hour on the far side of
    /// their day cannot reach it at all however long they have been logging.
    static let minimumSupport: Double = 6

    /// How much evidence must sit on *each* side of an hour, in day-equivalents.
    ///
    /// **A one-sided floor was the first design and the cohort refused it.** With
    /// `minimumSupport` alone, `SyntheticCohort.interpolator` — whose effect is
    /// planted at 07:00 and who logs 06:00 and 08:00 — produced this curve:
    ///
    /// ```
    /// 4:3.47(s14)  5:3.46(s29)  6:3.44(s43)  7:3.40(s48)  8:3.36(s42)
    /// ```
    ///
    /// Hours 04:00 and 05:00 score *above* the planted hour and clear a floor of 6
    /// comfortably. Nothing is wrong with the arithmetic: no hour is logged at the
    /// peak, so the smoothed curve plateaus across 06:00–08:00, and an hour just
    /// outside the earliest logged one inherits that plateau without the afternoon
    /// pulling it down. The argmax lands on an hour the person has never been awake
    /// for, which is the exact failure this feature exists to prevent, wearing a
    /// shape the total-support floor cannot see.
    ///
    /// `minimumSupport` answers "is this hour near anything?" — which catches
    /// `extrapolator`, whose support at 07:00 is 0.00. It cannot answer "is this hour
    /// *between* things?", and the two questions have different answers exactly at
    /// the edges of somebody's day. `PRD-HOURS.md` §2 draws the same line: an hour
    /// between hours they use is recoverable, an hour beyond them is not.
    ///
    /// So an hour must be surrounded: real kernel mass earlier *and* later. Half the
    /// total floor on each side, which is the weakest rule that still means
    /// "surrounded" rather than "near".
    static let minimumSideSupport: Double = minimumSupport / 2

    /// Distinct days needed before any shape is fitted.
    ///
    /// A curve over three days is a curve over three days however smooth it looks.
    static let minimumDays = 10

    // MARK: - Fitting

    /// Fit the shape, or return an empty one.
    ///
    /// **Clustered on days, like everything else in this engine.** Three sessions
    /// logged on one bad Tuesday are not three pieces of evidence about Tuesdays, and
    /// a smoother weighted by session would repeat exactly the pseudo-replication the
    /// day-clustered bootstrap exists to prevent — inflating support precisely for
    /// the people who log heavily, who are the people most likely to be reading the
    /// result. So each (day, hour) contributes one value: the median of whatever was
    /// logged there.
    ///
    /// **Medians at the day level, a weighted mean above it.** The robustness is
    /// bought where outliers actually live — a single bad session inside an hour —
    /// and the smoother above it is then an ordinary Nadaraya–Watson weighted mean,
    /// which is closed-form and can be checked by hand. A weighted median would be
    /// neither.
    ///
    /// **Workdays and days off are fitted apart**, as `Physiology.DayShape` already
    /// keeps them: somebody's 07:00 on a Saturday is not their 07:00 on a Tuesday,
    /// and pooling them would hand back an hour that is the average of two different
    /// lives.
    static func fit(
        _ observations: [EngineObservation],
        bandwidth: Double = bandwidth,
        minimumSupport: Double = minimumSupport,
        calendar: Calendar = .current
    ) -> Shape {
        var out: [Hour] = []
        for isWorkday in [true, false] {
            let points = dayPoints(observations.filter { $0.isWorkday == isWorkday },
                                   calendar: calendar)
            guard Set(points.map(\.day)).count >= minimumDays else { continue }

            for hour in 0..<24 {
                var weighted = 0.0
                var support = 0.0
                var earlier = 0.0
                var later = 0.0
                for point in points {
                    let weight = kernel(from: Double(hour), to: point.hour, bandwidth: bandwidth)
                    weighted += weight * point.rating
                    support += weight

                    // Which side of this hour the evidence sits on, the short way
                    // round. An hour logged exactly here counts for both, since it
                    // surrounds itself.
                    let ahead = (point.hour - Double(hour) + 24).truncatingRemainder(dividingBy: 24)
                    if ahead == 0 { earlier += weight; later += weight }
                    else if ahead < 12 { later += weight }
                    else { earlier += weight }
                }
                guard support >= minimumSupport,
                      earlier >= minimumSideSupport,
                      later >= minimumSideSupport else { continue }
                out.append(Hour(hour: hour, isWorkday: isWorkday,
                                estimate: weighted / support, support: support))
            }
        }
        return Shape(hours: out)
    }

    /// One rating per day per hour: the median of what was logged there.
    static func dayPoints(
        _ observations: [EngineObservation],
        calendar: Calendar = .current
    ) -> [(day: Date, hour: Double, rating: Double)] {
        var grouped: [Date: [Int: [Double]]] = [:]
        for observation in observations {
            guard let feeling = observation.feeling else { continue }
            let hour = calendar.component(.hour, from: observation.startAt)
            grouped[observation.day, default: [:]][hour, default: []].append(feeling)
        }

        var out: [(day: Date, hour: Double, rating: Double)] = []
        for (day, byHour) in grouped {
            for (hour, ratings) in byHour {
                guard let middle = median(ratings) else { continue }
                out.append((day: day, hour: Double(hour), rating: middle))
            }
        }
        // A stable order, so two fits over one history agree to the last bit.
        return out.sorted { ($0.day, $0.hour) < ($1.day, $1.hour) }
    }

    // MARK: - Arithmetic

    /// A wrapped Gaussian over hour-of-day.
    ///
    /// Wrapped because 23:00 and 01:00 are two hours apart, not twenty-two — the
    /// same distance `SyntheticCohort.hourTaper` measures, and a kernel that got it
    /// wrong would cut everybody's day in half at an arbitrary point.
    static func kernel(from: Double, to: Double, bandwidth: Double) -> Double {
        let raw = abs(from - to)
        let distance = min(raw, 24 - raw)
        return exp(-(distance * distance) / (2 * bandwidth * bandwidth))
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let half = sorted.count / 2
        if sorted.count.isMultiple(of: 2) { return (sorted[half - 1] + sorted[half]) / 2 }
        return sorted[half]
    }
}

private func < (lhs: (Date, Double), rhs: (Date, Double)) -> Bool {
    lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
}
