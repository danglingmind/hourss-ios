import Foundation
import Observation
import UserNotifications

/// Asking what you are doing, on a schedule, with no server anywhere.
///
/// The mechanism is deliberately dull: one repeating *calendar* alarm per hour of
/// the day, registered with iOS and then forgotten about. iOS fires them whether
/// Hourss has been opened in a week or not, which is the whole requirement — a
/// reminder that needs the app running to arrive is a reminder that never arrives.
///
/// The obvious alternative, `UNTimeIntervalNotificationTrigger(repeats: true)` at
/// 7200 seconds, was rejected for one reason: it has no idea what time it is. It
/// would fire at three in the morning, every night, forever, and there is no way
/// to bound it. Calendar triggers are bounded by construction, because each one
/// *is* a time of day.
enum LogReminders {

    /// Every request Hourss registers is named with this prefix, so its own
    /// reminders can be cleared without touching anything else the app might
    /// schedule later.
    static let identifierPrefix = "hourss.log-reminder."

    /// Marks a notification as "open the log sheet". Read on tap.
    static let actionKey = "hourss.action"
    static let logAction = "log"

    static func identifier(forHour hour: Int) -> String { "\(identifierPrefix)\(hour)" }

    /// What to ask. One question, in the voice the rest of the app uses.
    static let title = "What are you doing right now?"
    static let body = "One tap to log it."

    /// The hours to fire at, given a stated frequency and everything that can
    /// override it.
    ///
    /// Quiet mode is honoured here rather than at the call site, because this is
    /// the one function every scheduling path goes through — and a setting called
    /// "only what you ask for" that still sent fifteen notifications a day would
    /// be the single most damaging bug in this file.
    ///
    /// iOS caps an app at 64 pending requests. The busiest frequency here is
    /// fifteen, so the cap is never in play, but it is the reason this returns
    /// hours-per-day rather than anything that scales with how far ahead we look.
    static func hours(for profile: Profile) -> [Int] {
        guard !profile.quietMode else { return [] }
        return profile.logReminderFrequency.hours
    }
}

/// The part of scheduling that talks to iOS.
///
/// A protocol because `UNUserNotificationCenter` cannot be driven from a test —
/// it needs a real app, a real permission and a real clock — while everything
/// worth getting right is the decision about *which* hours, which is pure.
@MainActor
protocol LogReminderScheduling {
    /// Whether the person has already been asked, and said yes.
    func hasAuthorization() async -> Bool
    /// Raises the system prompt. Returns what they said.
    func requestAuthorization() async -> Bool
    /// Replaces every Hourss reminder with one per hour given. An empty array
    /// clears them.
    func replaceReminders(at hours: [Int]) async
    /// The hours currently registered, for tests and diagnostics.
    func scheduledHours() async -> [Int]
}

/// The real one.
@MainActor
struct SystemLogReminderScheduler: LogReminderScheduling {
    private var center: UNUserNotificationCenter { .current() }

    func hasAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    func requestAuthorization() async -> Bool {
        // No badge. A badge is an unread count, and Hourss has nothing to count —
        // a number on the icon that never goes down is a lie that has to be
        // cleared by hand.
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func replaceReminders(at hours: [Int]) async {
        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(LogReminders.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: existing)

        for hour in hours {
            let content = UNMutableNotificationContent()
            content.title = LogReminders.title
            content.body = LogReminders.body
            content.sound = .default
            content.userInfo = [LogReminders.actionKey: LogReminders.logAction]

            // Hour and minute only, so iOS repeats it daily in whatever timezone
            // the person is currently in. Pinning a date would send somebody's
            // 8am reminder at 3am the moment they flew anywhere.
            var when = DateComponents()
            when.hour = hour
            when.minute = 0

            let request = UNNotificationRequest(
                identifier: LogReminders.identifier(forHour: hour),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
            )
            try? await center.add(request)
        }
    }

    func scheduledHours() async -> [Int] {
        await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(LogReminders.identifierPrefix) }
            .compactMap { Int($0.identifier.dropFirst(LogReminders.identifierPrefix.count)) }
            .sorted()
    }
}

/// A scheduler that agrees to everything and does nothing.
///
/// For tests, and for UI tests in particular. The system permission prompt is
/// another process: XCTest cannot dismiss it without an interruption monitor, and
/// a suite that walks onboarding would stop dead at the reminders beat waiting for
/// an alert it cannot see. It also keeps a test run from registering real
/// repeating alarms on whatever simulator it happens to be using.
@MainActor
final class SilentLogReminderScheduler: LogReminderScheduling {
    private(set) var hours: [Int] = []
    private(set) var authorizationRequests = 0
    /// What `requestAuthorization` will answer, so both branches are testable.
    var grantsAuthorization: Bool
    private var granted: Bool

    init(granted: Bool = true, alreadyAuthorized: Bool = true) {
        self.grantsAuthorization = granted
        self.granted = alreadyAuthorized && granted
    }

    func hasAuthorization() async -> Bool { granted }

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        granted = grantsAuthorization
        return granted
    }

    func replaceReminders(at hours: [Int]) async { self.hours = hours }

    func scheduledHours() async -> [Int] { hours }
}

/// The app's one notification object: what is scheduled, and what a tap asked for.
@Observable
@MainActor
final class NotificationService {

    /// A singleton because iOS holds the delegate, weakly, from before any view
    /// exists. A tap that launches the app cold is delivered to whatever is
    /// registered at launch, so the object has to outlive every view and be
    /// reachable from `HourssApp.init()` — which an `@State` property is not.
    static let shared = NotificationService()

    /// Set when somebody taps a reminder, cleared when the app has acted on it.
    ///
    /// A token rather than a flag: tapping a second reminder while the sheet is
    /// already up has to read as a new request, and a `Bool` already true cannot
    /// say anything.
    private(set) var pendingLogRequest: UUID?

    /// Whether iOS will actually deliver anything. Read by the settings screen,
    /// which must not claim reminders are on when the system has them off.
    private(set) var isAuthorized = false

    private let scheduler: LogReminderScheduling
    /// Retained because `UNUserNotificationCenter.delegate` is weak.
    @ObservationIgnored private var forwarder: NotificationForwarder?

    init(scheduler: LogReminderScheduling? = nil) {
        #if DEBUG
        // `-hourss-debug-no-notifications`. Read straight from `ProcessInfo` and
        // compiled out of any build that is not DEBUG, so no shipped binary has a
        // path that silently declines to schedule what somebody asked for.
        if ProcessInfo.processInfo.arguments.contains(Self.debugLaunchArgument) {
            self.scheduler = SilentLogReminderScheduler()
            return
        }
        #endif
        self.scheduler = scheduler ?? SystemLogReminderScheduler()
    }

    #if DEBUG
    static let debugLaunchArgument = "-hourss-debug-no-notifications"
    #endif

    /// Start listening for taps. Called from `HourssApp.init()`.
    func startReceiving() {
        guard forwarder == nil else { return }
        let forwarder = NotificationForwarder { [weak self] in
            self?.receiveLogTap()
        }
        self.forwarder = forwarder
        UNUserNotificationCenter.current().delegate = forwarder
    }

    /// A reminder was tapped.
    ///
    /// Not private, because a notification cannot be delivered into a test process
    /// — the only way to exercise what a tap does is to say that one happened.
    func receiveLogTap() { pendingLogRequest = UUID() }

    func consumeLogRequest() { pendingLogRequest = nil }

    /// Ask iOS for permission, then put the schedule in place.
    ///
    /// Returns whether reminders will actually arrive, so the screen that asked
    /// can tell the truth about what just happened rather than assuming.
    @discardableResult
    func enableReminders(for profile: Profile) async -> Bool {
        guard profile.logReminderFrequency != .off else {
            await apply(profile)
            return false
        }
        var granted = await scheduler.hasAuthorization()
        if !granted { granted = await scheduler.requestAuthorization() }
        isAuthorized = granted
        await apply(profile)
        return granted
    }

    /// Bring the schedule in line with the profile.
    ///
    /// Idempotent, and cheap enough to run on every launch: it clears Hourss's own
    /// requests and re-adds them, so a schedule that drifted — a frequency changed
    /// on another launch, quiet mode toggled, iOS dropping requests — converges
    /// rather than needing to be reasoned about.
    func apply(_ profile: Profile) async {
        isAuthorized = await scheduler.hasAuthorization()
        // Nothing is scheduled without permission. iOS would discard them anyway,
        // and pending requests that can never fire make `scheduledHours()` lie.
        let hours = isAuthorized ? LogReminders.hours(for: profile) : []
        await scheduler.replaceReminders(at: hours)
    }

    func scheduledHours() async -> [Int] { await scheduler.scheduledHours() }

    #if DEBUG
    /// Fire one reminder a few seconds from now, for testing the tap.
    ///
    /// The real ones are daily calendar alarms, so the soonest is whenever the
    /// next scheduled hour comes round — which makes the tap behaviour untestable
    /// for up to a day. This carries the identical payload, so what it exercises
    /// is the real path and not a simulation of it.
    ///
    /// Written straight against `UNUserNotificationCenter` rather than through
    /// `LogReminderScheduling`, so the protocol stays free of it and no release
    /// build contains a path that can invent a reminder — the same reasoning the
    /// entitlement override and the fixture generator are gated by.
    @discardableResult
    func sendTestReminder(after seconds: TimeInterval = 5) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return false }

        let content = UNMutableNotificationContent()
        content.title = LogReminders.title
        content.body = LogReminders.body
        content.sound = .default
        content.userInfo = [LogReminders.actionKey: LogReminders.logAction]

        let request = UNNotificationRequest(
            identifier: "\(LogReminders.identifierPrefix)debug-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )
        try? await center.add(request)
        return true
    }
    #endif
}

/// The delegate, deliberately not actor-isolated.
///
/// Same reasoning as the Apple sign-in session: `UNUserNotificationCenterDelegate`
/// is an Objective-C protocol whose isolation belongs to the SDK, and a
/// `@MainActor` class witnessing it is a compile error waiting on an SDK revision.
private final class NotificationForwarder: NSObject, UNUserNotificationCenterDelegate {
    /// `@Sendable` so it can be handed to a main-actor task without carrying the
    /// delegate itself across the boundary — neither this object nor the system's
    /// completion handler is `Sendable`, and sending either is a data race the
    /// compiler is right to refuse.
    private let onLogTapped: @MainActor @Sendable () -> Void

    init(onLogTapped: @escaping @MainActor @Sendable () -> Void) {
        self.onLogTapped = onLogTapped
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.notification.request.content.userInfo[LogReminders.actionKey] as? String
        let isLog = action == LogReminders.logAction
        // Only a real tap opens the sheet. Dismissing a notification is a decision
        // not to log, and answering it by opening the logging sheet anyway would
        // be the app overruling them.
        let wasOpened = response.actionIdentifier == UNNotificationDefaultActionIdentifier

        if isLog && wasOpened {
            // The closure alone crosses over, copied out before the hop.
            let deliver = onLogTapped
            Task { @MainActor in deliver() }
        }

        // Called here rather than inside the task: iOS only needs to know this
        // delegate is done, and making it wait on a main-actor hop would hold up
        // notification delivery for no reason.
        completionHandler()
    }

    /// While Hourss is open and in front of somebody, a banner asking what they
    /// are doing is absurd — they are looking at the app that answers it.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }
}
