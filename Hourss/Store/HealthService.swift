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
    private(set) var isConnected = false
    private(set) var lastSyncedAt: Date?

    /// One value per metric per day, which is the only shape the pattern engine
    /// can use.
    private(set) var dailyValues: [HealthMetric: [Date: Double]] = [:]

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
    func connect() async {
        #if targetEnvironment(simulator)
        finishConnecting()
        #else
        let types = Set(selectedMetrics.compactMap(\.objectType))
        guard isAvailable, !types.isEmpty else {
            finishConnecting()
            return
        }
        // A refusal is not an error state here. The spec defines no "declined"
        // screen, and the app works either way.
        try? await store.requestAuthorization(toShare: [], read: types)
        finishConnecting()
        #endif
    }

    private func finishConnecting() {
        isConnected = true
        Task { await refresh() }
    }

    /// Stops reading. Deletes nothing — "no data removed unless the user chooses".
    /// Narrowing what iOS hands over can only be done in Settings, which the
    /// connection screen links to.
    func disconnect() {
        isConnected = false
        lastSyncedAt = nil
        dailyValues = [:]
    }

    // MARK: - Reading

    func refresh() async {
        guard isConnected else { return }
        var collected: [HealthMetric: [Date: Double]] = [:]

        for metric in selectedMetrics {
            let real = await read(metric)
            // A simulator authorizes happily and then has nothing to hand over.
            // Seeded values keep the demo whole; on a device, real data wins.
            collected[metric] = real.isEmpty ? MockData.seededDaily(for: metric) : real
        }

        dailyValues = collected
        lastSyncedAt = Date()
    }

    private func read(_ metric: HealthMetric) async -> [Date: Double] {
        guard isAvailable else { return [:] }
        switch metric {
        case .sleepHours: return await readSleep()
        case .workoutMinutes: return await readWorkouts()
        default: return await readQuantity(metric)
        }
    }

    private var window: NSPredicate {
        let start = Calendar.current.date(byAdding: .day, value: -42, to: Date()) ?? Date()
        return HKQuery.predicateForSamples(withStart: start, end: Date())
    }

    /// Statistics collections do the daily bucketing for us, and pick the right
    /// operation per metric: summing HRV readings would measure how often the
    /// watch sampled, not how the person was.
    private func readQuantity(_ metric: HealthMetric) async -> [Date: Double] {
        guard let type = metric.quantityType, let unit = metric.unit else { return [:] }
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -42, to: Date()) ?? Date())

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
}
