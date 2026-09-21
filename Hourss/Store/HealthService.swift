import Foundation
import HealthKit
import Observation

/// Optional Apple Health context.
///
/// Three rules from the spec shape this file:
///
/// 1. **Granular.** Consent is asked for in purpose groups, each naming the exact
///    types it reads — BR-16 requires access be "granular, optional, and explained
///    before the OS permission dialog."
/// 2. **Optional.** "The app remains fully usable without Health." Nothing here is
///    on a path anything else depends on.
/// 3. **Never medical.** These feed associations phrased "on days when…", compared
///    only against the person's own median. No reading, no diagnosis, no norm.
///
/// A note on scope: the PRD recommends deferring HRV. That was overridden
/// deliberately — the product's own positioning leads with "a work log paired with
/// signals from your body", and HRV is the signal people mean by that.
@Observable
@MainActor
final class HealthService {

    private let store = HKHealthStore()

    /// Groups the person chose. Selection is what we asked for, not what was
    /// granted — iOS never reports read authorization back, by design.
    var selectedGroups: Set<HealthGroup> = Set(HealthGroup.allCases)

    /// Whether the person has been through the connect flow, remembered across
    /// launches.
    ///
    /// It used to reset to false on every launch, which meant `refresh()` returned
    /// at its own guard and Health context was only ever as fresh as the last time
    /// somebody happened to open the connection screen. Harmless while the only
    /// consumer was the insight engine — which recomputes from sessions anyway —
    /// and not harmless at all now that a read is what puts last night on the
    /// record.
    private(set) var isConnected = false {
        didSet { UserDefaults.standard.set(isConnected, forKey: Self.connectedKey) }
    }
    private static let connectedKey = "hourss.health.connected"

    private(set) var lastSyncedAt: Date?

    init() {
        isConnected = UserDefaults.standard.bool(forKey: Self.connectedKey)
    }

    /// Whether the connection predates Hourss remembering connections.
    ///
    /// The flag above was added after people were already using the app, and
    /// onboarding — the only screen that asks for Health — never runs again once
    /// it is complete. So an existing person upgrading into that build had a
    /// connection Hourss had no record of and no route back to: no daily context,
    /// no physiology, no import, and nothing on any screen saying why.
    ///
    /// The absence of the key is the signal, and it is asked exactly once. Note
    /// that `.unnecessary` means the sheet has been answered, not that anything
    /// was granted — which is precisely what `isConnected` has always meant here,
    /// since iOS never reports a read grant either way.
    func restoreConnectionIfNeeded() async {
        // Keyed on the state rather than on whether the flag was ever written.
        //
        // The first version of this guarded on the key being absent and wrote
        // `false` when the answer was no — which permanently disabled the very
        // recovery it existed for, because one launch before somebody connected
        // was enough to make the key present forever. Asking "are we disconnected"
        // is self-healing: it costs one local query per launch until the answer
        // changes, and never runs again afterwards.
        guard !isConnected, isAvailable else { return }

        let types = Set(selectedMetrics.compactMap(\.objectType))
        guard !types.isEmpty else { return }

        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: types)
        guard Self.wasAlreadyAsked(status) else { return }

        #if DEBUG
        print("[Hourss.health] restored a connection made before it was remembered")
        #endif
        isConnected = true
    }

    /// The rule, separated so it can be tested without a device or a permission.
    static func wasAlreadyAsked(_ status: HKAuthorizationRequestStatus?) -> Bool {
        status == .unnecessary
    }

    /// One value per metric per day, which is the only shape the pattern engine
    /// can use.
    private(set) var dailyValues: [HealthMetric: [Date: Double]] = [:]

    /// Samples at their real timestamps, for layer 3.
    ///
    /// Deliberately separate from `dailyValues`, which is not a smaller version of
    /// this — it is a different measurement. `intervalComponents: DateComponents(day: 1)`
    /// collapses a day of heart rate to one number, and that collapse is our choice
    /// rather than an API limit. Per-session physiology needs the timestamps back.
    private(set) var physiology = Physiology.Feed()

    /// Whether anything read here came from HealthKit rather than being seeded.
    ///
    /// This is the only honest signal available about consent. iOS never reports a
    /// read grant, so a denial and an empty history are indistinguishable — but
    /// both mean the same thing to the product: there is nothing true to show.
    private(set) var hasRealData = false

    /// Whether this phone has ever handed over real Health data.
    ///
    /// Persisted, because it is the only thing that lets a revoked permission be
    /// told apart from an empty one. iOS never reports read authorization — a
    /// refusal and "nothing recorded" are the same answer — so the question
    /// cannot be asked directly and has to be inferred from a change: we had a
    /// year of readings yesterday, we have none today, and nothing else explains
    /// that.
    private var hasEverHadData: Bool {
        get { UserDefaults.standard.bool(forKey: "hourss.health.everHadData") }
        set { UserDefaults.standard.set(newValue, forKey: "hourss.health.everHadData") }
    }

    /// Access appears to have been withdrawn.
    ///
    /// Deliberately an inference and deliberately conservative. It fires only
    /// where this phone previously read real data and a full read now returns
    /// none, which no ordinary gap produces: a watch left on the charger still
    /// leaves steps, and a quiet week still leaves sleep. It cannot fire for
    /// somebody who never had data, which is the case that would otherwise lock
    /// out every new user, everybody without a watch, and anybody whose first
    /// read happened to be empty.
    private(set) var accessLost = false

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var selectedMetrics: [HealthMetric] {
        HealthMetric.allCases.filter { selectedGroups.contains($0.group) }
    }

    var connectedGroups: [HealthGroup] {
        isConnected ? HealthGroup.allCases.filter { selectedGroups.contains($0) } : []
    }

    // MARK: - Authorization

    /// Raises the real iOS Health sheet, only after an explicit in-app tap.
    ///
    /// Simulators are handled separately, and not for convenience: a simulator
    /// build is ad-hoc signed, so the HealthKit entitlement is not honoured, the
    /// sheet half-presents and never resolves, and the window wedges. There is no
    /// Health data on a simulator either, so it goes straight to seeded values.
    /// Devices get the real prompt, with nothing racing the person reading it.
    /// Ask again after access was withdrawn.
    ///
    /// `requestAuthorization` will not re-present the sheet once somebody has
    /// answered it — iOS treats that as settled — so the only route back is the
    /// Settings app, and the button that calls this has to say so rather than
    /// appearing to do something it cannot.
    func recheckAccess() async {
        await refresh()
    }

    func connect() async {
        #if targetEnvironment(simulator)
        await finishConnecting()
        #else
        let types = Set(selectedMetrics.compactMap(\.objectType))
        guard isAvailable, !types.isEmpty else {
            await finishConnecting()
            return
        }
        // A refusal is not an error state here. The spec defines no "declined"
        // screen, and the app works either way.
        try? await store.requestAuthorization(toShare: [], read: types)
        await finishConnecting()
        #endif
    }

    /// Awaits the read rather than firing it detached. The old version returned
    /// before any data existed, so the caller's `applyHealthContext` always ran
    /// against an empty dictionary and Health context never reached an insight.
    private func finishConnecting() async {
        isConnected = true
        await refresh()
    }

    /// Stops reading. Deletes nothing — "no data removed unless the user chooses".
    /// Narrowing what iOS hands over can only be done in Settings, which the
    /// connection screen links to.
    func disconnect() {
        isConnected = false
        lastSyncedAt = nil
        dailyValues = [:]
        physiology = Physiology.Feed()
        hasRealData = false
    }

    // MARK: - Reading

    /// Reads every selected metric. Awaitable, and concurrent — ten serial round
    /// trips is what made the data arrive too late to show during onboarding.
    func refresh() async {
        guard isConnected else { return }
        let metrics = selectedMetrics

        let collected = await withTaskGroup(of: (HealthMetric, [Date: Double]).self) { group in
            for metric in metrics {
                group.addTask { [weak self] in
                    guard let self else { return (metric, [:]) }
                    return (metric, await self.read(metric))
                }
            }
            var result: [HealthMetric: [Date: Double]] = [:]
            for await (metric, values) in group { result[metric] = values }
            return result
        }

        let anythingReal = collected.values.contains { !$0.isEmpty }

        // An empty read stays empty, on a simulator as much as on a phone.
        //
        // This used to substitute generated values whenever HealthKit returned
        // nothing, which on a device meant somebody who declined the permission
        // got a connected badge and insights carrying confidence bands computed
        // from data the app invented. The simulator branch survived that fix and
        // is going the same way: a simulator with no Health data should look like
        // what it is.
        dailyValues = collected

        // The inference, and the only place it is drawn.
        let gotSomething = collected.values.contains { !$0.isEmpty }
        if gotSomething {
            hasEverHadData = true
            accessLost = false
        } else if hasEverHadData {
            accessLost = true
        }

        let feed = await readPhysiology()
        physiology = feed
        if !feed.isEmpty { hasRealData = true }

        lastSyncedAt = Date()
    }

    private func read(_ metric: HealthMetric) async -> [Date: Double] {
        guard isAvailable else { return [:] }
        // Heart rate is authorized for and then never read daily: its daily mean
        // measures how much somebody walked and how often the watch sampled. It
        // arrives through `readPhysiology()` instead, with its timestamps intact.
        guard metric.isDailyContext else { return [:] }
        switch metric {
        case .sleepHours: return await readSleep()
        case .workoutMinutes: return await readWorkouts()
        default: return await readQuantity(metric)
        }
    }

    /// A year. The insight engine only compares the recent six weeks, but the
    /// onboarding digest is looking for what is already true about someone, and
    /// six weeks is too thin to find a weekday rhythm worth showing.
    static let historyDays = 365

    private var windowStart: Date {
        Calendar.current.date(byAdding: .day, value: -Self.historyDays, to: Date()) ?? Date()
    }

    private var window: NSPredicate {
        HKQuery.predicateForSamples(withStart: windowStart, end: Date())
    }

    /// Statistics collections do the daily bucketing for us, and pick the right
    /// operation per metric: summing HRV readings would measure how often the
    /// watch sampled, not how the person was.
    private func readQuantity(_ metric: HealthMetric) async -> [Date: Double] {
        guard let type = metric.quantityType, let unit = metric.unit else { return [:] }
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: windowStart)

        let collection: HKStatisticsCollection? = await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: window,
                options: metric.isCumulative ? .cumulativeSum : .discreteAverage,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, _ in continuation.resume(returning: results) }
            store.execute(query)
        }

        guard let collection else { return [:] }
        var byDay: [Date: Double] = [:]
        collection.enumerateStatistics(from: anchor, to: Date()) { statistics, _ in
            let quantity = metric.isCumulative ? statistics.sumQuantity() : statistics.averageQuantity()
            guard let quantity else { return }
            byDay[calendar.startOfDay(for: statistics.startDate)] = quantity.doubleValue(for: unit)
        }
        return byDay
    }

    private func readSleep() async -> [Date: Double] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [:] }
        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: window, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                continuation.resume(returning: results as? [HKCategorySample] ?? [])
            }
            store.execute(query)
        }

        let calendar = Calendar.current
        var byMorning: [Date: Double] = [:]
        for sample in samples {
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value),
                  HKCategoryValueSleepAnalysis.allAsleepValues.contains(value) else { continue }
            // A night belongs to the morning it ends on — the day whose sessions it
            // could plausibly bear on.
            let morning = calendar.startOfDay(for: sample.endDate)
            byMorning[morning, default: 0] += sample.endDate.timeIntervalSince(sample.startDate) / 3600
        }
        return byMorning
    }

    private func readWorkouts() async -> [Date: Double] {
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: window, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                continuation.resume(returning: results as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }

        let calendar = Calendar.current
        var byDay: [Date: Double] = [:]
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startDate)
            byDay[day, default: 0] += workout.duration / 60
        }
        return byDay
    }

    // MARK: - Importable blocks

    /// How far back the importer fills in.
    ///
    /// Six weeks, not the year `historyDays` reads. The year exists for the
    /// onboarding digest, which is hunting a weekday rhythm and needs the length;
    /// sessions are a record of what somebody did, and the engine never compares
    /// beyond six weeks. Filling a year of Journal with rows nobody was there for
    /// would make the archive look lived-in without being lived in.
    static let importDays = 42

    /// Workouts and nights, as blocks ready to become sessions.
    ///
    /// Consent is respected group by group, the same way reading is: somebody who
    /// left Movement off has not agreed to have their workouts written onto their
    /// own record, and an importer that ignored that would be taking more than the
    /// screen asked for.
    func readImportableSessions() async -> [HealthImport.Candidate] {
        guard isConnected, isAvailable else { return [] }
        async let workouts = readWorkoutBlocks()
        async let sleep = readSleepBlocks()

        let workoutCandidates = HealthImport.candidates(workouts: await workouts)
        let sleepCandidates = HealthImport.candidates(sleep: await sleep)

        #if DEBUG
        // Kept, in DEBUG only. Whether Health hands anything over is invisible
        // from inside the app — an empty read and a refused one look identical —
        // and without a count here the difference between "no workouts recorded"
        // and "the importer never ran" cannot be told apart from the Journal.
        print("[Hourss.import] read \(workoutCandidates.count) workouts, \(sleepCandidates.count) nights")
        #endif

        return workoutCandidates + sleepCandidates
    }

    private var importWindow: NSPredicate {
        let start = Calendar.current.date(byAdding: .day, value: -Self.importDays, to: Date()) ?? Date()
        return HKQuery.predicateForSamples(withStart: start, end: Date())
    }

    private func readWorkoutBlocks() async -> [HealthImport.Workout] {
        guard selectedGroups.contains(.movement) else { return [] }
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: importWindow,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                continuation.resume(returning: results as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }
        return workouts.map {
            HealthImport.Workout(
                id: $0.uuid,
                span: HealthImport.Span(start: $0.startDate, end: $0.endDate)
            )
        }
    }

    /// Every stretch Health scored as asleep. Clustering them into nights is
    /// `HealthImport`'s job, not this one's.
    private func readSleepBlocks() async -> [HealthImport.Span] {
        guard selectedGroups.contains(.sleep),
              let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: importWindow,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                continuation.resume(returning: results as? [HKCategorySample] ?? [])
            }
            store.execute(query)
        }

        return samples.compactMap { sample in
            // "In bed" is not sleep, and counting it would hand somebody a Rest
            // block for the hour they spent reading.
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value),
                  HKCategoryValueSleepAnalysis.allAsleepValues.contains(value) else { return nil }
            return HealthImport.Span(start: sample.startDate, end: sample.endDate)
        }
    }

    // MARK: - Sample-level reading

    /// How far back layer 3 looks.
    ///
    /// Shorter than `historyDays` on purpose. The digest wants a year because it is
    /// hunting for a weekday rhythm; the residual only ever compares a session
    /// against the recent six weeks, and a year of heart rate at one sample every
    /// few minutes is a hundred thousand values to hold in memory for nothing.
    static let physiologyDays = 60

    /// Heart rate and steps with their timestamps, plus workouts as lead-in
    /// exclusions. The existing daily path is untouched — other code depends on it,
    /// and this answers a different question.
    func readPhysiology() async -> Physiology.Feed {
        guard isConnected, isAvailable, selectedGroups.contains(.recovery) else {
            return Physiology.Feed()
        }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -Self.physiologyDays, to: end) ?? end

        async let beats = heartRateSamples(from: start, to: end)
        async let paces = stepSamples(from: start, to: end)
        async let exercise = vigorousWindows(from: start, to: end)
        return await Physiology.Feed(heartRate: beats, steps: paces, vigorous: exercise)
    }

    /// Heart rate as individual samples.
    ///
    /// `HKSampleQuery` rather than a statistics collection: heart rate is a
    /// discrete type whose value is the reading, and bucketing it to a fixed grid
    /// would average away the irregular sampling that is the whole reason it can be
    /// attributed to a session at all.
    private func heartRateSamples(from start: Date, to end: Date) async -> [Physiology.Sample] {
        guard let type = HealthMetric.heartRate.quantityType,
              let unit = HealthMetric.heartRate.unit else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sortByTime = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sortByTime
            ) { _, results, _ in
                continuation.resume(returning: results as? [HKQuantitySample] ?? [])
            }
            store.execute(query)
        }
        return samples.map { Physiology.Sample(at: $0.startDate, value: $0.quantity.doubleValue(for: unit)) }
    }

    /// Steps in five-minute buckets.
    ///
    /// A statistics collection here, and for the opposite reason to heart rate:
    /// summing raw step samples double-counts, because the iPhone and the Watch
    /// both record the same walk and HealthKit stores both. `HKStatisticsCollectionQuery`
    /// applies Apple's own source-merging, so the totals are the ones Health itself
    /// shows. Five minutes is fine enough that a cadence over a forty-minute window
    /// is a pace rather than a smear, and coarse enough to stay cheap.
    private func stepSamples(from start: Date, to end: Date) async -> [Physiology.Sample] {
        guard let type = HealthMetric.steps.quantityType else { return [] }
        let anchor = Calendar.current.startOfDay(for: start)

        let collection: HKStatisticsCollection? = await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: DateComponents(minute: 5)
            )
            query.initialResultsHandler = { _, results, _ in continuation.resume(returning: results) }
            store.execute(query)
        }

        guard let collection else { return [] }
        var out: [Physiology.Sample] = []
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            guard let sum = statistics.sumQuantity() else { return }
            out.append(Physiology.Sample(at: statistics.startDate, value: sum.doubleValue(for: .count())))
        }
        return out
    }

    /// Workouts, as windows a session's baseline must not sit downstream of.
    ///
    /// Every workout counts, not only the hard ones: HealthKit reports no intensity
    /// worth trusting across activity types, and heart rate stays elevated after an
    /// easy hour as well as a fast one. Under ten minutes is dropped as a mis-start.
    private func vigorousWindows(from start: Date, to end: Date) async -> [DateInterval] {
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, _ in
                continuation.resume(returning: results as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }
        return workouts
            .filter { $0.duration >= 600 }
            .map { DateInterval(start: $0.startDate, end: $0.endDate) }
    }
}
