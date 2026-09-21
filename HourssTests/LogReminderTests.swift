import Testing
import Foundation
@testable import Hourss

/// Asking what you are doing, on a schedule, with nothing but the phone.
///
/// The mechanism is repeating daily alarms registered with iOS, which means the
/// decisions worth testing are all made before anything leaves the app: which
/// hours, and whether to schedule at all. Everything after that is `UNUserNotification`
/// doing its job.
@Suite("Log reminders")
@MainActor
struct LogReminderTests {

    // MARK: - The schedule itself

    /// Each row on the picker states its own cost — "15 a day", "8 a day". Those
    /// are promises about what the phone will do, made in copy that lives a long
    /// way from the schedule, so they are asserted against it rather than trusted.
    @Test("Every frequency delivers exactly what its row claims")
    func statedCountsAreTrue() {
        #expect(LogReminderFrequency.hourly.hours.count == 15)
        #expect(LogReminderFrequency.everyTwoHours.hours.count == 8)
        #expect(LogReminderFrequency.everyThreeHours.hours.count == 5)
        #expect(LogReminderFrequency.twiceDaily.hours.count == 2)
        #expect(LogReminderFrequency.off.hours.isEmpty)
    }

    /// The one rule that must never break, whatever else changes. A reminder at
    /// 3am is not a reminder, it is a reason to turn the app off in Settings — a
    /// decision Hourss cannot undo and will never be asked about again.
    @Test("Nothing is ever scheduled overnight")
    func nothingFiresOvernight() {
        for frequency in LogReminderFrequency.allCases {
            for hour in frequency.hours {
                #expect(hour >= 8, "\(frequency.title) would fire at \(hour):00")
                #expect(hour <= 22, "\(frequency.title) would fire at \(hour):00")
            }
        }
    }

    @Test("Frequencies are offered most frequent first, with off last")
    func offIsTheLastOption() {
        #expect(LogReminderFrequency.offered.last == .off)
        #expect(LogReminderFrequency.offered.contains(.recommended))
    }

    // MARK: - What the profile does to it

    private func profile(_ frequency: LogReminderFrequency, quiet: Bool = false) -> Profile {
        var profile = Profile()
        profile.logReminder = frequency
        profile.quietMode = quiet
        return profile
    }

    /// "Only what you ask for" has to actually stop them. A quiet mode that still
    /// sent eight notifications a day would be the single most damaging bug here.
    @Test("Quiet mode silences every frequency")
    func quietModeSilencesEverything() {
        for frequency in LogReminderFrequency.allCases {
            #expect(LogReminders.hours(for: profile(frequency, quiet: true)).isEmpty,
                    "\(frequency.title) survived quiet mode")
        }
    }

    @Test("A profile from before reminders existed is silent")
    func unchosenMeansOff() {
        // `logReminder` is nil for every record written before this feature. Nobody
        // is opted into notifications they were never offered.
        let untouched = Profile()
        #expect(untouched.logReminderFrequency == .off)
        #expect(LogReminders.hours(for: untouched).isEmpty)
    }

    // MARK: - Talking to iOS

    @Test("Choosing a frequency asks for permission once, then schedules it")
    func enablingAsksThenSchedules() async {
        let scheduler = SilentLogReminderScheduler(granted: true, alreadyAuthorized: false)
        let service = NotificationService(scheduler: scheduler)

        let granted = await service.enableReminders(for: profile(.everyTwoHours))

        #expect(granted)
        #expect(scheduler.authorizationRequests == 1)
        #expect(await service.scheduledHours() == LogReminderFrequency.everyTwoHours.hours)
    }

    @Test("Already having permission does not prompt again")
    func alreadyAuthorizedDoesNotPrompt() async {
        let scheduler = SilentLogReminderScheduler(granted: true, alreadyAuthorized: true)
        let service = NotificationService(scheduler: scheduler)

        await service.enableReminders(for: profile(.hourly))

        #expect(scheduler.authorizationRequests == 0)
        #expect(await service.scheduledHours() == LogReminderFrequency.hourly.hours)
    }

    /// iOS would discard them anyway, and pending requests that can never fire
    /// make the settings screen claim reminders are on when they are not.
    @Test("A refusal schedules nothing")
    func refusalSchedulesNothing() async {
        let scheduler = SilentLogReminderScheduler(granted: false, alreadyAuthorized: false)
        let service = NotificationService(scheduler: scheduler)

        let granted = await service.enableReminders(for: profile(.everyTwoHours))

        #expect(granted == false)
        #expect(service.isAuthorized == false)
        #expect(await service.scheduledHours() == [])
    }

    /// Choosing "don't remind me" must not raise a system prompt. Asking for
    /// permission to send nothing is the most irritating thing an app can do.
    @Test("Choosing off never raises the system prompt")
    func offNeverPrompts() async {
        let scheduler = SilentLogReminderScheduler(granted: true, alreadyAuthorized: false)
        let service = NotificationService(scheduler: scheduler)

        await service.enableReminders(for: profile(.off))

        #expect(scheduler.authorizationRequests == 0)
        #expect(await service.scheduledHours() == [])
    }

    /// Runs on every launch, so it has to converge rather than accumulate.
    @Test("Applying twice leaves one schedule, and a changed frequency replaces it")
    func applyingIsIdempotent() async {
        let scheduler = SilentLogReminderScheduler()
        let service = NotificationService(scheduler: scheduler)

        await service.apply(profile(.hourly))
        await service.apply(profile(.hourly))
        #expect(await service.scheduledHours() == LogReminderFrequency.hourly.hours)

        await service.apply(profile(.twiceDaily))
        #expect(await service.scheduledHours() == LogReminderFrequency.twiceDaily.hours)
    }

    @Test("Turning quiet mode on clears what was already scheduled")
    func quietModeClearsExistingReminders() async {
        let scheduler = SilentLogReminderScheduler()
        let service = NotificationService(scheduler: scheduler)

        await service.apply(profile(.everyTwoHours))
        #expect(await service.scheduledHours().isEmpty == false)

        await service.apply(profile(.everyTwoHours, quiet: true))
        #expect(await service.scheduledHours().isEmpty)
    }

    // MARK: - The tap

    /// A token rather than a flag, so a second tap while the sheet is already open
    /// reads as a new request — a `Bool` already true can say nothing.
    @Test("A tap is a fresh request every time")
    func tapsAreDistinct() {
        let service = NotificationService(scheduler: SilentLogReminderScheduler())
        #expect(service.pendingLogRequest == nil)

        service.receiveLogTap()
        let first = service.pendingLogRequest
        #expect(first != nil)

        service.consumeLogRequest()
        #expect(service.pendingLogRequest == nil)

        service.receiveLogTap()
        #expect(service.pendingLogRequest != nil)
        #expect(service.pendingLogRequest != first)
    }
}
