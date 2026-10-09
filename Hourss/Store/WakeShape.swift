import Foundation

/// When this person usually gets up.
///
/// **Why the app needs this at all.** Every hour the engine can name is a clock
/// hour, and a clock hour is not the person's time. 07:00 is ninety minutes into
/// the day for somebody who wakes at 05:30 and an hour before the day starts for
/// somebody who wakes at 08:00 — so an offer to put something at 07:00 is useful
/// advice to the first and an instruction to get up early to the second, which is
/// not a thing this app may ask anybody to do. `PRD-HOURS.md` §3.3.
///
/// **It costs nothing to read.** Health's sleep is already imported as sessions —
/// `HealthImport.candidates(sleep:)` picks the longest block ending on each
/// morning, and `HourssStore.importFromHealth` writes it to the record with its
/// real start and end. So a wake time is the `endAt` of a night already on the
/// record: no new HealthKit query, no new permission, nothing added to the consent
/// screen, and it works offline because the nights are stored rather than fetched.
///
/// **What it refuses, and why that matters more than what it returns.** A usual
/// waking time is a claim that somebody *has* a usual waking time. Plenty of people
/// do not: shift workers, new parents, anybody whose week is split between early
/// starts and late ones. For them the median of their wake times is a number that
/// describes none of their mornings, and acting on it would be worse than having no
/// number at all — the app would confidently anchor every suggestion to an hour
/// they are rarely awake for.
///
/// So this refuses twice: when there are too few nights to say anything, and when
/// the nights that exist do not agree with each other. The second is the one that
/// earns its keep, and `maximumSpread` is the whole of it.
enum WakeShape {

    /// Nights needed before a usual time means anything.
    ///
    /// Ten rather than the engine's six. Six is the floor for *comparing* two sides
    /// of a split, where the correction and the interval carry the uncertainty that
    /// remains. Nothing downstream of this carries any: the wake time is used as a
    /// gate and as a phrase, both of which either happen or do not. A number with no
    /// interval around it should be asked for on more evidence, not less.
    static let minimumNights = 10

    /// How far apart the middle half of somebody's wake times may sit and still be
    /// called one habit, in minutes.
    ///
    /// The interquartile range rather than the full spread, because one holiday lie-in
    /// in sixty nights is not evidence that somebody has no routine, and a rule that
    /// treated it as such would refuse almost everybody. Two hours is wide enough to
    /// hold an ordinary weekend and narrow enough that a genuinely split week fails
    /// it — somebody alternating 06:00 starts with 10:00 ones has an IQR near four
    /// hours and gets nil, which is the honest answer.
    ///
    /// Not derived from anything. It is the answer to "how different can your
    /// mornings be before you do not have a usual one", which is a judgement, and it
    /// is stated here so it can be argued with rather than discovered in a formula.
    static let maximumSpread = 120

    /// Minutes after midnight, or nil when this person has no usual waking time.
    ///
    /// Clock minutes rather than a `Date` because the answer is a time of day and
    /// not an instant: it is compared against the hour an offer wants to name, and a
    /// `Date` would carry a calendar day that means nothing here.
    static func usualWake(from sessions: [Session], calendar: Calendar = .current) -> Int? {
        let minutes = wakeMinutes(from: sessions, calendar: calendar)
        guard minutes.count >= minimumNights else { return nil }

        let sorted = minutes.sorted()
        guard let middle = median(sorted), spread(sorted) <= maximumSpread else { return nil }
        return middle
    }

    /// Every night on the record, as the minute of the day it ended.
    ///
    /// **Nights that cross noon are dropped rather than wrapped.** A block Health
    /// scored as sleep ending at 15:00 is either a long nap or a night shift, and
    /// this cannot tell them apart. Wrapping it into the circular arithmetic would
    /// let one afternoon nap drag a whole routine later; dropping it costs a real
    /// night shift its answer, and `usualWake` returning nil for a night worker is
    /// the outcome this file is written to produce anyway.
    static func wakeMinutes(from sessions: [Session], calendar: Calendar = .current) -> [Int] {
        sessions.compactMap { session in
            guard session.healthKind == .sleep, let end = session.endAt else { return nil }
            let parts = calendar.dateComponents([.hour, .minute], from: end)
            guard let hour = parts.hour, let minute = parts.minute, hour < 12 else { return nil }
            return hour * 60 + minute
        }
    }

    /// Whether an hour of the clock is one this person is up for.
    ///
    /// **The gate, and the half of this file that matters.** An offer naming an hour
    /// before somebody is awake is an instruction to get up earlier wearing the
    /// costume of a suggestion about their day, and `PRD-LOCKS.md` §6 refuses to ask
    /// anybody to do anything they did not come here to do.
    ///
    /// True when there is no usual waking time, deliberately. Without one the app
    /// knows nothing about when this person is up, and a gate that refuses on
    /// ignorance would silence every offer for everybody whose sleep Health never
    /// recorded — which is a larger harm than occasionally naming an early hour to
    /// somebody the app has no information about. The gate narrows what is offered
    /// when it knows something; it does not invent knowledge to narrow with.
    static func isAwake(at hour: Int, wake: Int?) -> Bool {
        guard let wake else { return true }
        return hour * 60 >= wake
    }

    // MARK: - Arithmetic

    /// The middle value, averaging the two middles on an even count.
    private static func median(_ sorted: [Int]) -> Int? {
        guard !sorted.isEmpty else { return nil }
        let half = sorted.count / 2
        if sorted.count.isMultiple(of: 2) { return (sorted[half - 1] + sorted[half]) / 2 }
        return sorted[half]
    }

    /// The interquartile range, in minutes.
    private static func spread(_ sorted: [Int]) -> Int {
        guard sorted.count >= 4 else { return 0 }
        let low = sorted[sorted.count / 4]
        let high = sorted[(sorted.count * 3) / 4]
        return high - low
    }
}
