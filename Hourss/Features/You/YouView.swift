import SwiftUI

enum YouRoute: Hashable {
    case preferences, privacy, health
}

/// Y1 — a settings list, not a dashboard.
///
/// The surfaces that need Clerk, HealthKit or StoreKit (Y2, Y4, Y5) appear as
/// visibly disabled rows. Showing them greyed reads as deliberately scoped;
/// hiding them would make the shell look like it forgot them, and mocking them
/// would imply working auth and health integration.
struct YouView: View {
    @Environment(HourssStore.self) private var store
    @Environment(HealthService.self) private var health

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
                    NavigationLink(value: YouRoute.privacy) {
                        SettingsRow(title: "Privacy & data", detail: "Export, delete, what's stored")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("row-privacy")
                    HRule()
                }

                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow("Not in this build")
                        .padding(.bottom, Space.xs)
                    HRule()
                    SettingsRow(title: "Profile", detail: "Needs an account", enabled: false)
                    HRule()
                    SettingsRow(title: "Membership", detail: "Needs StoreKit", enabled: false)
                    HRule()
                }

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
            case .preferences: PreferencesView()
            case .privacy: PrivacyView()
            case .health: HealthConnectionView()
            }
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
struct PreferencesView: View {
    @Environment(HourssStore.self) private var store

    var body: some View {
        @Bindable var store = store

        return ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                DisplayHeadline([Text("Preferences").styled(.sectionTitle)], style: .sectionTitle)
                    .padding(.top, Space.md)

                VStack(spacing: 0) {
                    HRule()
                    EditorialToggle(
                        title: "Log prompts",
                        detail: "Max 3 a week.",
                        isOn: $store.profile.logPrompts
                    )
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

                VStack(alignment: .leading, spacing: Space.sm) {
                    Eyebrow("Reflection time")
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
    }
}

/// Y6 — plain-language data controls.
struct PrivacyView: View {
    @State private var exportRequested = false

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
                    SettingsRow(title: "Delete account", detail: "Needs an account", enabled: false)
                    HRule()
                }
            }
            .pageGutter()
            .padding(.bottom, Space.xl)
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .top, spacing: 0) { BackHeader(title: "You") }
        .navigationBarBackButtonHidden()
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
                                store.applyHealthContext(health.dailyValues)
                                store.applyPhysiology(feed: await health.readPhysiology())
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
