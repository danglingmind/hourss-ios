import Foundation

/// One fact a day out of the history this person already has.
///
/// Onboarding spends the three most striking things in a year of Health history
/// on a single screen, and then the app goes quiet: Today shows nothing that did
/// not come from logging. Everything below onboarding's top three is still true
/// and still theirs, so this rations it — one fact per calendar day, on the
/// screen they open anyway, requiring nothing of them first.
///
/// Rationing is the design, not an optimisation. The pool is finite and the
/// facts in it do not get truer for being repeated; a fact a day for as long as
/// the history lasts is a reason to open the app, and the same fact twice is a
/// reason to stop believing the first one.
///
/// A value rather than an object: every bit of its memory lives in
/// `UserDefaults`, so two copies made a second apart cannot disagree, and the
/// view holding one does not have to keep it alive across a redraw.
struct DailyFact {

    private let defaults: UserDefaults
    private let calendar: Calendar

    /// House pattern: one namespaced key per stored thing, named where it is read.
    private static let spentStorageKey = "hourss.dailyFact.spent"
    private static let dayStorageKey = "hourss.dailyFact.day"

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    /// A fact's identity, stable across builds.
    ///
    /// `HealthDigest.Fact.id` is a fresh `UUID()` per build and the digest is
    /// rebuilt on every launch, so the id says nothing about whether two facts
    /// are the same fact. Metric and kind are what a fact *is*: the four
    /// generators each run at most once per metric, so the pair is unique within
    /// a pool, and it is the same spelling the prior table is keyed by.
    static func key(for fact: HealthDigest.Fact) -> String {
        "\(fact.subject.key).\(HealthDigest.kindKey(fact.kind))"
    }

    /// Everything dispensed so far, oldest first. The last entry is the fact the
    /// next one has to be unlike.
    var spentKeys: [String] { defaults.stringArray(forKey: Self.spentStorageKey) ?? [] }

    /// This day's fact, or nil once the pool is used up.
    ///
    /// Idempotent within a calendar day. A view body is re-evaluated for reasons
    /// that have nothing to do with the date — a keystroke elsewhere, a session
    /// starting — and a dispenser that handed out a new fact per call would spend
    /// the year in an afternoon.
    /// `record` is offered ahead of `health`, not merged into it.
    ///
    /// Merging was the obvious thing and it is wrong. `surprise` scores an
    /// unknown prior at half a bit while a strong Health prior reaches better
    /// than four, and a record fact has no prior by construction — so in one
    /// ranked list record facts sort below nearly every Health fact and only
    /// surface once the Health pool is spent, five weeks in. That is precisely
    /// backwards: a record fact is the one that exists *because* somebody logged,
    /// so it is the one that has to arrive while they are deciding whether
    /// logging is worth it.
    ///
    /// So the record is asked first, every day, and Health fills in behind it.
    /// Early on there is no record to draw from and Health carries the whole
    /// thing; as the log grows the record takes over. That is the handoff this
    /// feature was supposed to have.
    func fact(for day: Date,
              record: [HealthDigest.Fact] = [],
              from health: [HealthDigest.Fact]) -> HealthDigest.Fact? {
        let today = dayKey(day)
        var spent = spentKeys
        let pool = record + health

        // Already dispensed today: hand back the same fact, found by content
        // rather than by identity.
        if defaults.string(forKey: Self.dayStorageKey) == today,
           let held = spent.last,
           let fact = pool.first(where: { Self.key(for: $0) == held }) {
            return fact
        }
        // Falling through here means today's fact is no longer in the pool — the
        // history it rested on moved under it, which a Health sync can do. Its key
        // stays spent, because it was shown, and today draws again rather than
        // going blank for the rest of the day.

        let alreadyShown = Set(spent)
        // Record facts sit at the head of the list and the Health half arrives
        // ranked by surprise behind them, so "first" is "best" throughout — but
        // "best" now means "the record before the watch", not "the largest
        // surprise". See the note on this method.
        let remaining = pool.filter { !alreadyShown.contains(Self.key(for: $0)) }
        // Exhausted. Nothing is recycled and nothing is invented to fill the
        // space: a person who has seen everything their history holds is owed
        // silence, not a fact they have already read or one that is not a fact.
        guard !remaining.isEmpty else { return nil }

        // Variety as a cascade, strongest preference first.
        //
        // Yesterday alone was not enough. Avoiding only the previous fact stops
        // two sleep facts landing on consecutive mornings but does nothing about
        // day one and day five, and nothing at all about the real duplication:
        // the four movement metrics are correlated by construction, so
        // "your step count has been running higher lately" and "your active
        // energy has been running higher lately" are one fact told twice, and a
        // metric-level rule sees two different metrics and lets both through.
        //
        // So the hard axis is the pair (group, kind) — the topic and the shape —
        // which is the same rule `build` applies to onboarding's three, extended
        // over the whole run. Sixteen combinations exist, so sixteen genuinely
        // distinct days come first, and what remains after that is the
        // repetitive tail, arriving when the engine has its own things to say.
        let previous = spent.last
        let seenPairs = Set(spent.compactMap(Self.pair(ofKey:)))

        func isNewPair(_ fact: HealthDigest.Fact) -> Bool {
            !seenPairs.contains(Self.pair(of: fact))
        }
        func unlikeYesterday(_ fact: HealthDigest.Fact) -> Bool {
            !repeats(previous, with: fact)
        }

        // Written as a list rather than a chain of `??`: four trailing closures
        // joined by nil-coalescing is also what the type checker gave up on.
        let preferences: [(HealthDigest.Fact) -> Bool] = [
            { isNewPair($0) && unlikeYesterday($0) },
            { isNewPair($0) },
            { unlikeYesterday($0) },
        ]
        let chosen = preferences.lazy.compactMap { remaining.first(where: $0) }.first ?? remaining[0]
        // The final fallback is deliberate and matches how `build` fills its
        // third row: when variety cannot be had, variety is what gets dropped.
        // Holding any of these absolutely would mean showing nothing on a day
        // facts still exist for, and the pool is finite — a person who has run
        // out of new shapes has not run out of true things about themselves.

        spent.append(Self.key(for: chosen))
        defaults.set(spent, forKey: Self.spentStorageKey)
        defaults.set(today, forKey: Self.dayStorageKey)
        return chosen
    }

    /// Topic and shape — what makes two facts feel like one.
    ///
    /// Group rather than metric on purpose. Metric says steps and active energy
    /// are different subjects; a reader looking at both cards knows they are the
    /// same day being described twice, because one is a consequence of the other.
    /// `HealthGroup` is the level at which two facts are actually about different
    /// things.
    static func pair(of fact: HealthDigest.Fact) -> String {
        "\(fact.subject.varietyKey).\(HealthDigest.kindKey(fact.kind))"
    }

    /// A stored key taken apart into the subject it names and the kind it is.
    ///
    /// **Split from the end, not the front.** A Health key is `steps.drift` and
    /// splits either way, but a record key is `record.ratings.best` — three
    /// components, because the subject is itself namespaced. The kind is always
    /// the last component and the subject is everything before it, so reading
    /// backwards is the only rule that holds for both. Splitting from the front
    /// silently produced a subject of `record` and a kind of `ratings.best`,
    /// which matched nothing and disabled variety control for exactly the facts
    /// that were added to improve it.
    static func parts(ofKey key: String) -> (subject: String, kind: String)? {
        let components = key.split(separator: ".")
        guard components.count >= 2, let kind = components.last else { return nil }
        return (components.dropLast().joined(separator: "."), String(kind))
    }

    /// The variety pair recovered from a stored key.
    ///
    /// The stored subject is a metric for Health facts, and the variety axis is
    /// its group, so that lookup has to happen here. Nil when the metric no
    /// longer exists in the enum: a fact whose metric has been removed cannot
    /// block anything, which is the right failure — the alternative is guessing
    /// at a group and silently suppressing a fact that has nothing to do with it.
    ///
    /// A record subject is already at group level, because a topic is the
    /// coarsest thing it has. So `key` and its pair are the same string, and
    /// there is nothing to look up.
    static func pair(ofKey key: String) -> String? {
        guard let (subject, kind) = parts(ofKey: key) else { return nil }
        if subject.hasPrefix("record.") { return key }
        guard let metric = HealthMetric(rawValue: subject) else { return nil }
        return "\(metric.group.rawValue).\(kind)"
    }

    /// Whether a candidate repeats the previous fact's subject or its kind.
    ///
    /// Compared against the stored key rather than against a decoded metric: the
    /// key is the only thing that survives a launch, and a subject that has since
    /// been removed from its enum should still be recognised as the thing shown
    /// yesterday.
    private func repeats(_ previousKey: String?, with fact: HealthDigest.Fact) -> Bool {
        guard let previousKey, let (subject, kind) = Self.parts(ofKey: previousKey) else { return false }
        return subject == fact.subject.key || kind == HealthDigest.kindKey(fact.kind)
    }

    /// A day as a sortable, locale-independent key — the same shape the importer
    /// writes into the record, and for the same reason: this string outlives a
    /// flight to another timezone and a change of region.
    private func dayKey(_ day: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
