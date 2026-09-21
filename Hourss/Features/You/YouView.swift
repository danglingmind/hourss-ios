import SwiftUI

enum YouRoute: Hashable {
    case profile, preferences, privacy, health, account
}

/// Y1 — a settings list, not a dashboard.
///
/// Nothing here is greyed out any more. The account row (Y2) was the last of the
/// disabled ones and is now real: Sign in with Apple, against no server, so what
/// it controls is who this record is for rather than where it is kept.
///
/// Membership (Y5) is the remaining half-answer. It has no purchase behind it
/// yet, but the tier is real state that Today's observation slot varies on, so the
/// row states it rather than standing in for it.
struct YouView: View {
    @Environment(HourssStore.self) private var store
    @Environment(HealthService.self) private var health
    @Environment(AccountService.self) private var account

    /// One route to entitlement, through the object every screen here already
    /// holds, so no screen can end up reading a different answer.
    private var membership: Membership { store.membership }

    /// What the profile currently says, led by whichever part of it the person
    /// has actually set. Ranked priorities come first because they are the part
    /// that changes what the app says back.
    private var profileDetail: String {
        let priorities = store.profile.priorities
        if !priorities.isEmpty {
            return priorities.map(\.title).joined(separator: ", ")
        }
        return store.profile.displayName.isEmpty ? "Name, priorities, workdays" : store.profile.displayName
    }

    /// The name if Apple shared one, the plain fact if it did not. Never an
    /// email — the row sits on a screen somebody might hand to a friend, and a
    /// relay address is still an address.
    private var accountDetail: String {
        guard let signedIn = account.account else { return "Not signed in" }
        return signedIn.fullName ?? "Signed in with Apple"
    }

    private var healthDetail: String {
        guard health.isConnected else { return "Not connected" }
        let names = health.connectedGroups.map(\.title).joined(separator: ", ")
        return names.isEmpty ? "Connected" : names
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                summary

                VStack(spacing: 0) {
                    HRule()
                    NavigationLink(value: YouRoute.profile) {
                        SettingsRow(title: "Profile", detail: profileDetail)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("row-profile")
                    HRule()
                    NavigationLink(value: YouRoute.preferences) {
                        SettingsRow(title: "Preferences", detail: "Prompts, timing, quiet mode")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("row-preferences")
                    HRule()
                    NavigationLink(value: YouRoute.health) {
                        SettingsRow(title: "Health connection", detail: healthDetail)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("row-health")
                    HRule()
                    NavigationLink(value: YouRoute.account) {
                        SettingsRow(title: "Account", detail: accountDetail)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("row-account")
                    HRule()
                    NavigationLink(value: YouRoute.privacy) {
                        SettingsRow(title: "Privacy & data", detail: "Export, delete, what's stored")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("row-privacy")
                    HRule()
                }

                membershipSection

                Text("Hourss is a personal record, not a productivity score. Nothing here is shared.")
                    .textStyle(.label)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .pageGutter()
            .padding(.bottom, Space.xl)
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .top, spacing: 0) { ScreenHeader(title: "You") }
        .navigationDestination(for: YouRoute.self) { route in
            switch route {
            case .profile: ProfileView()
            case .preferences: PreferencesView()
            case .privacy: PrivacyView()
            case .health: HealthConnectionView()
            case .account: AccountView()
            }
        }
    }

    /// Membership, which is real state now that the observation slot on Today
    /// varies on it — so it leaves the disabled group even though there is still
    /// nothing to buy. A debug build switches it in place; a release build states
    /// where the person stands and offers no control, because the only honest
    /// control is a purchase and there is not one yet.
    ///
    /// The caption is not a pitch. It is the boundary: what membership adds, and
    /// what it will never sit in front of.
    private var membershipSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("Membership")
                .padding(.bottom, Space.xs)
            HRule()
            #if DEBUG
            Button {
                membership.setTier(membership.isEntitled ? .free : .member)
            } label: {
                SettingsRow(
                    title: "Membership",
                    detail: "\(membership.tier.settingsDetail) — tap to switch (debug)"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("row-membership")
            #else
            SettingsRow(title: "Membership", detail: membership.tier.settingsDetail, enabled: false)
                .accessibilityIdentifier("row-membership")
            #endif
            HRule()

            Text("Membership adds recommendations. Your own record is never behind it — export, deletion and every privacy setting stay free.")
                .textStyle(.label)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.xs)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            DisplayHeadline([
                Text(store.profile.displayName.isEmpty ? "You" : store.profile.displayName).styled(.sectionTitle),
            ], style: .sectionTitle)
            .padding(.top, Space.md)

            Text("\(store.sessions.filter { !$0.isRunning }.count) sessions logged · \(store.loggedDays.count) days")
                .textStyle(.label)
                .foregroundStyle(Color.muted)
        }
    }
}

struct SettingsRow: View {
    let title: String
    var detail: String?
    var enabled: Bool = true

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).textStyle(.stepName)
                if let detail {
                    Text(detail).textStyle(.label).foregroundStyle(Color.muted)
                }
            }
            Spacer()
            if enabled {
                Text("→").font(.custom("DMSans-Bold", fixedSize: 18)).foregroundStyle(Color.orange)
            }
        }
        .padding(.vertical, Space.sm)
        .frame(minHeight: Space.tapTarget)
        .opacity(enabled ? 1 : 0.35)
        .contentShape(.rect)
        .accessibilityAddTraits(enabled ? [] : [.isStaticText])
    }
}

/// Y3 — granular toggles, with quiet mode suppressing the non-essential prompts.
///
/// Nothing on this screen used to be saved. Every control bound straight into
/// `store.profile`, which is an in-memory object, and no path from here ever
/// reached `persist()` — so a preference survived until the app was closed and
/// not one moment longer. It went unnoticed because none of these settings did
/// anything yet; log reminders are the first that leave the app, and a frequency
/// that silently reverted overnight would have looked like iOS dropping
/// notifications rather than like this.
struct PreferencesView: View {
    @Environment(HourssStore.self) private var store
    @Environment(NotificationService.self) private var notifications
    #if DEBUG
    /// nil until a test reminder has been asked for; false means iOS refused.
    @State private var testReminderSent: Bool?
    #endif

    var body: some View {
        @Bindable var store = store

        return ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                DisplayHeadline([Text("Preferences").styled(.sectionTitle)], style: .sectionTitle)
                    .padding(.top, Space.md)

                reminders

                VStack(spacing: 0) {
                    HRule()
                    EditorialToggle(
                        title: "Weekly reflection",
                        detail: "Weekly, after 3+ sessions.",
                        isOn: $store.profile.weeklyReflection
                    )
                    HRule()
                    EditorialToggle(
                        title: "Quiet mode",
                        detail: "Only what you ask for.",
                        isOn: $store.profile.quietMode
                    )
                    HRule()
                }
                .onChange(of: store.profile.weeklyReflection) { _, _ in store.persist() }
                .onChange(of: store.profile.quietMode) { _, _ in
                    store.persist()
                    // Quiet mode is the one toggle here that reaches outside the
                    // app: "only what you ask for" has to actually stop the
                    // reminders, not merely record a preference about them.
                    Task { await notifications.apply(store.profile) }
                }

                VStack(alignment: .leading, spacing: Space.sm) {
                    Eyebrow("Reflection time")
                        .accessibilityIdentifier("reflection-time")
                    Text("\(store.profile.reflectionHour):00")
                        .textStyle(.dayNumeral)
                    HStack(spacing: Space.md) {
                        Button("Earlier") {
                            store.profile.reflectionHour = max(16, store.profile.reflectionHour - 1)
                        }
                        .buttonStyle(.plain)
                        .textStyle(.action)
                        .frame(minHeight: Space.tapTarget)

                        Button("Later") {
                            store.profile.reflectionHour = min(23, store.profile.reflectionHour + 1)
                        }
                        .buttonStyle(.plain)
                        .textStyle(.action)
                        .frame(minHeight: Space.tapTarget)
                    }
                }
            }
            .pageGutter()
            .padding(.bottom, Space.xl)
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .top, spacing: 0) { BackHeader(title: "You") }
        .navigationBarBackButtonHidden()
        .onChange(of: store.profile.reflectionHour) { _, _ in store.persist() }
    }

    /// How often Hourss asks what you are doing.
    ///
    /// The caption is the honest part. iOS owns whether anything is delivered, and
    /// somebody who turned Hourss off in Settings must not be shown a screen
    /// cheerfully claiming eight reminders a day — so the state reported here is
    /// the system's answer, not ours.
    private var reminders: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Eyebrow("Log reminders")

            LogReminderPicker(selection: Binding(
                get: { store.profile.logReminderFrequency },
                set: { updated in
                    store.profile.logReminder = updated
                    store.persist()
                    Task { await notifications.enableReminders(for: store.profile) }
                }
            ))

            Text(reminderCaption)
                .textStyle(.label)
                .foregroundStyle(reminderCaptionIsWarning ? Color.orange : Color.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reminder-status")

            #if DEBUG
            // The real reminders are daily alarms, so the next one can be most of
            // a day away — which makes the thing most worth checking, what a tap
            // does, impossible to check. Debug builds only.
            VStack(spacing: 0) {
                HRule()
                Button {
                    Task { testReminderSent = await notifications.sendTestReminder() }
                } label: {
                    SettingsRow(
                        title: "Send one now",
                        detail: testReminderSent == false
                            ? "Notifications are off for Hourss in Settings"
                            : "Arrives in 5 seconds — leave the app to see it (debug)"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("send-test-reminder")
                HRule()
            }
            #endif
        }
    }

    private var isSilenced: Bool {
        store.profile.logReminderFrequency != .off
            && (store.profile.quietMode || !notifications.isAuthorized)
    }

    private var reminderCaptionIsWarning: Bool { isSilenced }

    private var reminderCaption: String {
        guard store.profile.logReminderFrequency != .off else {
            return "Hourss will not send anything."
        }
        if store.profile.quietMode {
            return "Quiet mode is on, so these are not being sent."
        }
        if !notifications.isAuthorized {
            return "Notifications are turned off for Hourss in Settings, so these are not being sent."
        }
        return "Never overnight. Tapping one opens the activity list."
    }
}

/// Y6 — plain-language data controls.
///
/// Deletion is real here, and it is the whole of it. Hourss has no server, so
/// there is no second copy to reconcile with and nothing to queue for a backend
/// to catch up on: clearing the record and the Keychain item *is* the account
/// being deleted, which is also what Apple requires of anything offering sign-in.
struct PrivacyView: View {
    @Environment(HourssStore.self) private var store
    @Environment(AccountService.self) private var account
    @Environment(HealthService.self) private var health
    @State private var exportRequested = false
    @State private var isConfirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                DisplayHeadline([
                    Text("Your data").styled(.sectionTitle),
                    Text("stays ").styled(.sectionTitle).then(Text("yours.").styled(.emphasis(42))),
                ], style: .sectionTitle)
                .padding(.top, Space.md)

                VStack(alignment: .leading, spacing: Space.sm) {
                    HRule()
                    ForEach([
                        "Your sessions, ratings and notes are stored for you and nobody else.",
                        "Observations are computed from your own history — never compared against other people.",
                        "Nothing is sold, shared, or used for advertising.",
                    ], id: \.self) { line in
                        Text("— \(line)")
                            .textStyle(.body)
                            .foregroundStyle(Color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 2)
                    }
                }

                VStack(spacing: 0) {
                    HRule()
                    Button {
                        exportRequested = true
                    } label: {
                        SettingsRow(title: "Export everything", detail: exportRequested ? "Requested — we'll email a file" : "A file with every session and note")
                    }
                    .buttonStyle(.plain)
                    HRule()
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        SettingsRow(title: "Delete everything", detail: "Your account and every session, for good")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("delete-everything")
                    HRule()
                }
            }
            .pageGutter()
            .padding(.bottom, Space.xl)
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .top, spacing: 0) { BackHeader(title: "You") }
        .navigationBarBackButtonHidden()
        .confirmationDialog("Delete everything?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { deleteEverything() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every session, rating and note on this iPhone is erased, you are signed out, and Health is disconnected so nothing flows back in. Hourss keeps no copy anywhere else, so there is nothing to restore this from.")
        }
    }

    /// The record, then the connection that would refill it, then the account.
    ///
    /// Disconnecting Health is not housekeeping — it is the difference between
    /// this doing what its dialog says and not. The importer runs on every launch
    /// and back-fills six weeks, so a deletion that left the connection open would
    /// put last month's sleep and workouts straight back on a record somebody had
    /// just been told was erased. Onboarding asks for Health again on its second
    /// beat, so nothing is lost that they are not offered back.
    ///
    /// The account goes last because signing out is what the root watches: it
    /// swaps the whole screen, and doing it first would tear this view down
    /// mid-deletion with the record still on disk.
    private func deleteEverything() {
        store.deleteEverything()
        health.disconnect()
        account.signOut()
    }
}

/// A flat toggle. `Switch` styling is the one place iOS chrome is worth keeping —
/// it is universally understood — but the row around it stays editorial.
private struct EditorialToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).textStyle(.stepName)
                Text(detail)
                    .textStyle(.label)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(.lime)
        .padding(.vertical, Space.sm)
        .frame(minHeight: Space.tapTarget)
    }
}

struct BackHeader: View {
    @Environment(\.dismiss) private var dismiss
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Text("←").font(.custom("DMSans-Bold", fixedSize: 18)).foregroundStyle(Color.orange)
                        Text(title).textStyle(.action)
                    }
                    .frame(minHeight: Space.tapTarget)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("back")
                Spacer()
            }
            .pageGutter()
            HRule()
        }
        .background(Color.canvas)
    }
}

/// Y4 — the Health connection.
///
/// Shows what was consented to, when it last read, and how to change it. Two
/// things are deliberate: disconnecting stops reading but deletes nothing ("no
/// data removed unless the user chooses"), and narrowing scope hands off to
/// Settings, because iOS only lets Health permissions be reduced there.
struct HealthConnectionView: View {
    @Environment(HealthService.self) private var health
    @Environment(HourssStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                DisplayHeadline([
                    Text("Apple").styled(.sectionTitle),
                    Text("Health.").styled(.emphasis(42)),
                ], style: .sectionTitle)
                .padding(.top, Space.md)

                VStack(alignment: .leading, spacing: Space.xs) {
                    Eyebrow(health.isConnected ? "Connected" : "Not connected")
                    if let synced = health.lastSyncedAt {
                        Text("Last read \(synced.formatted(.dateTime.hour().minute()))")
                            .textStyle(.label)
                            .foregroundStyle(Color.muted)
                    }
                }

                VStack(spacing: 0) {
                    HRule()
                    ForEach(HealthGroup.allCases) { group in
                        let on = health.isConnected && health.selectedGroups.contains(group)
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.title).textStyle(.stepName)
                                Text(group.scopeDescription)
                                    .textStyle(.label)
                                    .foregroundStyle(Color.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: Space.sm)
                            SelectionDot(isSelected: on)
                                .padding(.top, 4)
                        }
                        .padding(.vertical, Space.sm)
                        .frame(minHeight: Space.tapTarget)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(group.title): \(on ? "on" : "off"). Reads \(group.scopeDescription)")
                        HRule()
                    }
                }

                VStack(spacing: 0) {
                    if health.isConnected {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            SettingsRow(title: "Change what Hourss reads", detail: "Opens Settings")
                        }
                        .buttonStyle(.plain)
                        HRule()

                        Button {
                            health.disconnect()
                            store.applyHealthContext([:])
                            store.applyPhysiology([:])
                        } label: {
                            SettingsRow(title: "Disconnect", detail: "Stops reading. Nothing is deleted.")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("health-disconnect")
                        HRule()
                    } else {
                        Button {
                            Task {
                                await health.connect()
                                await applyHealthRead(from: health, to: store)
                            }
                        } label: {
                            SettingsRow(title: "Connect Health", detail: "Sleep, recovery, movement, daylight")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("health-connect")
                        HRule()
                    }
                }

                Text("Read only. Nothing is written back to Health.")
                    .textStyle(.label)
                    .foregroundStyle(Color.muted)
            }
            .pageGutter()
            .padding(.bottom, Space.xl)
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .top, spacing: 0) { BackHeader(title: "You") }
        .navigationBarBackButtonHidden()
    }
}
