import SwiftUI

enum YouRoute: Hashable {
    case preferences, privacy
}

/// Y1 — a settings list, not a dashboard.
///
/// The surfaces that need Clerk, HealthKit or StoreKit (Y2, Y4, Y5) appear as
/// visibly disabled rows. Showing them greyed reads as deliberately scoped;
/// hiding them would make the shell look like it forgot them, and mocking them
/// would imply working auth and health integration.
struct YouView: View {
    @Environment(HourssStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                summary

                VStack(spacing: 0) {
                    HRule()
                    NavigationLink(value: YouRoute.preferences) {
                        SettingsRow(title: "Preferences", detail: "Prompts, reflection time, quiet mode")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("row-preferences")
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
                    SettingsRow(title: "Health connection", detail: "Needs HealthKit", enabled: false)
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

            if !store.profile.goals.isEmpty {
                Text("Here for \(store.profile.goals.map(\.title).sorted().joined(separator: ", ").lowercased())")
                    .textStyle(.body)
                    .foregroundStyle(Color.muted)
                    .padding(.top, Space.xs)
            }
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
                        detail: "One close-out nudge, at most three times a week.",
                        isOn: $store.profile.logPrompts
                    )
                    HRule()
                    EditorialToggle(
                        title: "Weekly reflection",
                        detail: "A digest once a week, if you logged at least three sessions.",
                        isOn: $store.profile.weeklyReflection
                    )
                    HRule()
                    EditorialToggle(
                        title: "Quiet mode",
                        detail: "Suppresses everything except what you ask for.",
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
