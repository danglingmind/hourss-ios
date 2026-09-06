import Foundation
import HealthKit

/// A daily context value the pattern engine can associate with how sessions felt.
///
/// Every metric here reduces to **one number per day**, because that is the only
/// shape the association algorithm consumes: split a person's rated sessions by
/// whether that day's value sat above or below their own median, and compare.
/// Anything that cannot be summarised daily — a VO2 max that updates monthly — is
/// not a context signal.
///
/// `heartRate` is the one deliberate exception, and it is not a daily context
/// signal either. It is here so the type appears in the consent scope and in the
/// authorization request, because layer 3 reads its *samples* at their real
/// timestamps. Its daily mean is never computed: averaging a day of heart rate
/// measures how much somebody moved and how often the watch happened to sample,
/// which is not a fact about them. `isDailyContext` marks the difference and
/// `HealthService.read(_:)` enforces it.
enum HealthMetric: String, CaseIterable, Identifiable {
    // Sleep
    case sleepHours

    // Recovery
    case hrv
    case restingHeartRate
    case respiratoryRate

    /// Raw heart rate, read per sample rather than per day.
    ///
    /// The only *dense* type Apple Health carries — every few minutes at rest,
    /// every few seconds during a workout — and therefore the only one that can be
    /// attributed to a single logged session at all. Layer 3 is built on it.
    ///
    /// The two neighbours above cannot do this job, and no amount of querying
    /// changes that. **HRV (SDNN)** arrives a handful of times a day, almost all of
    /// it overnight or during a Breathe session, so an hourly query returns mostly
    /// empty windows and the rest are selected by when the watch chose to measure;
    /// it keeps its one honest job, an overnight value read against the following
    /// morning. **Resting heart rate** is one value per day by Apple's own
    /// construction rather than by our aggregation, so it cannot be windowed at
    /// all. Steps and active energy are dense, and are the movement covariates.
    case heartRate

    // Movement
    case workoutMinutes
    case steps
    case activeEnergy
    case exerciseMinutes

    // Mind and light
    case mindfulMinutes
    case daylightMinutes

    var id: String { rawValue }

    var group: HealthGroup {
        switch self {
        case .sleepHours: .sleep
        case .hrv, .restingHeartRate, .respiratoryRate, .heartRate: .recovery
        case .workoutMinutes, .steps, .activeEnergy, .exerciseMinutes: .movement
        case .mindfulMinutes, .daylightMinutes: .mind
        }
    }

    /// Shown in the consent list so the scope is visible before the OS dialog.
    var title: String {
        switch self {
        case .sleepHours: "Time asleep"
        case .hrv: "Heart rate variability"
        case .restingHeartRate: "Resting heart rate"
        case .respiratoryRate: "Respiratory rate"
        case .heartRate: "Heart rate"
        case .workoutMinutes: "Workouts"
        case .steps: "Steps"
        case .activeEnergy: "Active energy"
        case .exerciseMinutes: "Exercise minutes"
        case .mindfulMinutes: "Mindful minutes"
        case .daylightMinutes: "Time in daylight"
        }
    }

    /// How an observation names the high side of this metric. Always relative to
    /// the person's own median — never to a population, and never as a verdict.
    var higherPhrase: String {
        switch self {
        case .sleepHours: "after a longer night"
        case .hrv: "when your heart rate variability ran higher"
        case .restingHeartRate: "when your resting heart rate ran higher"
        case .respiratoryRate: "when your breathing ran faster"
        // Unused: heart rate is never split on as a daily value. Present only
        // because the protocol is exhaustive.
        case .heartRate: "when your heart rate ran higher"
        case .workoutMinutes: "after a longer workout"
        case .steps: "when you walked more"
        case .activeEnergy: "when you moved more"
        case .exerciseMinutes: "after more exercise"
        case .mindfulMinutes: "after more quiet time"
        case .daylightMinutes: "after more time outside"
        }
    }

    var lowerPhrase: String {
        switch self {
        case .sleepHours: "after a shorter night"
        case .hrv: "when it ran lower"
        case .restingHeartRate: "when it ran lower"
        case .respiratoryRate: "when it ran slower"
        case .heartRate: "when it ran lower"
        case .workoutMinutes: "after a shorter one"
        case .steps: "when you walked less"
        case .activeEnergy: "when you moved less"
        case .exerciseMinutes: "after less"
        case .mindfulMinutes: "after less"
        case .daylightMinutes: "after less"
        }
    }

    /// What the two comparison bars are labelled.
    var highLabel: String {
        switch self {
        case .sleepHours: "Longer nights"
        case .hrv: "Higher HRV"
        case .restingHeartRate: "Higher resting HR"
        case .respiratoryRate: "Faster breathing"
        case .heartRate: "Higher heart rate"
        case .workoutMinutes: "More workout time"
        case .steps: "More steps"
        case .activeEnergy: "More active energy"
        case .exerciseMinutes: "More exercise"
        case .mindfulMinutes: "More quiet time"
        case .daylightMinutes: "More daylight"
        }
    }

    var lowLabel: String {
        switch self {
        case .sleepHours: "Shorter nights"
        case .hrv: "Lower HRV"
        case .restingHeartRate: "Lower resting HR"
        case .respiratoryRate: "Slower breathing"
        case .heartRate: "Lower heart rate"
        case .workoutMinutes: "Less workout time"
        case .steps: "Fewer steps"
        case .activeEnergy: "Less active energy"
        case .exerciseMinutes: "Less exercise"
        case .mindfulMinutes: "Less quiet time"
        case .daylightMinutes: "Less daylight"
        }
    }

    /// The caveat that travels with every observation built on this metric. A
    /// business rule requires health context carry one, and forbids inferring
    /// anything causal or medical from it.
    var caveat: String {
        switch self {
        case .sleepHours: "A longer night often comes with an easier day."
        case .hrv: "HRV moves with a lot of things. This is an association, not a reading of your health."
        case .restingHeartRate: "Resting heart rate drifts for many reasons, including how it was measured."
        case .respiratoryRate: "Breathing rate varies with measurement conditions as much as with you."
        case .heartRate: "Heart rate mostly tracks what your body was doing at the time."
        case .workoutMinutes: "The days you train may differ in other ways too."
        case .steps: "Busy days and walkable days are not the same thing."
        case .activeEnergy: "Movement and the kind of day you had tend to travel together."
        case .exerciseMinutes: "The days you exercise may already be your lighter ones."
        case .mindfulMinutes: "Quiet time may follow a good day as easily as cause one."
        case .daylightMinutes: "Time outside tracks the weather and your schedule too."
        }
    }

    var objectType: HKObjectType? {
        switch self {
        case .sleepHours: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .hrv: HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case .restingHeartRate: HKObjectType.quantityType(forIdentifier: .restingHeartRate)
        case .respiratoryRate: HKObjectType.quantityType(forIdentifier: .respiratoryRate)
        case .heartRate: HKObjectType.quantityType(forIdentifier: .heartRate)
        case .workoutMinutes: HKObjectType.workoutType()
        case .steps: HKObjectType.quantityType(forIdentifier: .stepCount)
        case .activeEnergy: HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        case .exerciseMinutes: HKObjectType.quantityType(forIdentifier: .appleExerciseTime)
        case .mindfulMinutes: HKObjectType.categoryType(forIdentifier: .mindfulSession)
        case .daylightMinutes: HKObjectType.quantityType(forIdentifier: .timeInDaylight)
        }
    }

    var quantityType: HKQuantityType? { objectType as? HKQuantityType }

    /// Whether a day's samples should be summed or averaged. Getting this wrong
    /// makes the number meaningless: totalling HRV readings measures how often the
    /// watch sampled, not how the person was.
    var isCumulative: Bool {
        switch self {
        case .steps, .activeEnergy, .exerciseMinutes, .mindfulMinutes, .daylightMinutes, .workoutMinutes, .sleepHours:
            true
        case .hrv, .restingHeartRate, .respiratoryRate, .heartRate:
            false
        }
    }

    /// Whether this metric is a daily context signal the association engine may
    /// split on.
    ///
    /// False only for `heartRate`, which is read for its samples. A day's mean
    /// heart rate is dominated by how much somebody walked and by how often the
    /// watch sampled, so a claim built on it would be a claim about their commute
    /// wearing the language of physiology. Layer 3 exists precisely because that
    /// number is not worth having.
    var isDailyContext: Bool { self != .heartRate }

    var unit: HKUnit? {
        switch self {
        case .hrv: .secondUnit(with: .milli)
        case .restingHeartRate, .respiratoryRate, .heartRate: HKUnit.count().unitDivided(by: .minute())
        case .steps: .count()
        case .activeEnergy: .kilocalorie()
        case .exerciseMinutes, .mindfulMinutes, .daylightMinutes: .minute()
        case .sleepHours, .workoutMinutes: nil   // derived from sample durations
        }
    }
}

/// Consent is asked for in purpose groups rather than ten separate switches.
///
/// BR-16 requires access be "granular, optional, and explained before the OS
/// permission dialog", with the acceptance test being that "consent scope is
/// displayed" — so each group names exactly which types it reads. Per-type
/// granularity still exists where it is enforceable: in the iOS sheet itself,
/// which lists every type individually and is the only place a grant is real.
enum HealthGroup: String, CaseIterable, Identifiable {
    case sleep, recovery, movement, mind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: "Sleep"
        case .recovery: "Recovery"
        case .movement: "Movement"
        case .mind: "Mind and light"
        }
    }

    /// What consenting to this group buys you.
    var benefit: String {
        switch self {
        case .sleep: "How mornings go after a longer night"
        case .recovery: "What your body was doing around your better hours"
        case .movement: "Whether moving changes the rest of the day"
        case .mind: "What quiet time and daylight sit next to"
        }
    }

    var metrics: [HealthMetric] { HealthMetric.allCases.filter { $0.group == self } }

    /// The exact scope, shown under the group so nothing is consented to blind.
    var scopeDescription: String {
        metrics.map(\.title).joined(separator: " · ")
    }
}
