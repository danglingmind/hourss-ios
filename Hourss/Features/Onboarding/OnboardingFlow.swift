import SwiftUI

/// O1 → O9, minus the screens that need a real backend.
///
/// Health (O6), notifications (O7) and account (O8) depend on HealthKit, the
/// system notification sheet and Clerk, so they are out of the shell rather than
/// faked — the spec is explicit that permission screens must precede the real
/// system prompt, and a mock one would teach the wrong thing.
struct OnboardingFlow: View {
    @Environment(HourssStore.self) private var store
    @State private var step = 0

    private let stepCount = 5

    var body: some View {
        VStack(spacing: 0) {
            header

            // Scrollable, but only when it needs to be. At large Dynamic Type the
            // steps outgrow the screen and would otherwise push the footer — and
            // the Continue button with it — out of reach.
            GeometryReader { geo in
                ScrollView {
                    Group {
                        switch step {
                        case 0: WelcomeStep()
                        case 1: NoticeStep()
                        case 2: IntentStep()
                        case 3: ActivitiesStep()
                        default: FirstLogStep(onFinish: finish)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            footer
        }
        .surface(step == 0 ? .forest : .canvas)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Wordmark()
                Spacer()
                if step > 0 {
                    Text("\(step + 1) / \(stepCount)").textStyle(.label)
                }
            }
            .pageGutter()
            .padding(.vertical, Space.gutter)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            HRule()
            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.plain)
                        .textStyle(.action)
                        .frame(minHeight: Space.tapTarget)
                }
                Spacer()
                if step < stepCount - 1 {
                    DirectionalLink(title: step == 0 ? "Start" : "Continue", arrow: "→") {
                        guard canContinue else { return }
                        step += 1
                    }
                    .disabled(!canContinue)
                }
            }
            .pageGutter()
            .padding(.bottom, Space.xs)
        }
    }

    /// The activities step is the one place a choice is required. Everything else
    /// is optional by design, but leaving with nothing kept would mean no activity
    /// to log against — an app that cannot do the one thing it is for.
    private var canContinue: Bool {
        step == 3 ? store.favoriteCount > 0 : true
    }

    private func finish() {
        store.hasCompletedOnboarding = true
    }
}

/// O1 — the value statement, on the forest surface so it lands as a moment rather
/// than a settings page.
private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Spacer()
            Eyebrow("Know your good hours")
            DisplayHeadline([
                Text("Your hours").styled(.display),
                Text("have a ").styled(.display).then(Text("pattern.").styled(.emphasis(58))),
            ])
            Text("Hourss keeps a quiet record of how your time actually feels, then shows you what repeats. Nothing to optimise. Nothing to score.")
                .textStyle(.body)
                .foregroundStyle(Color.mutedOnDark)
                .frame(maxWidth: 340, alignment: .leading)
            Spacer()
            Text("Your data stays yours.")
                .textStyle(.label)
                .foregroundStyle(Color.subtleOnDark)
        }
        .pageGutter()
        .padding(.vertical, Space.lg)
    }
}

/// O2 — three illustrative examples, explicitly labelled as examples.
private struct NoticeStep: View {
    private let examples: [(String, String, String)] = [
        ("Timing", "When a kind of work tends to feel better", "Deep work before 11am"),
        ("Energy", "Which activities give energy back", "A walk without a podcast"),
        ("Conditions", "What repeats around your better days", "After a longer night's sleep"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Eyebrow("What Hourss notices")
            DisplayHeadline([
                Text("Three kinds").styled(.sectionTitle),
                Text("of ").styled(.sectionTitle).then(Text("noticing.").styled(.emphasis(42))),
            ], style: .sectionTitle)

            VStack(spacing: 0) {
                HRule()
                ForEach(examples, id: \.0) { name, blurb, example in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(name).textStyle(.stepName)
                        Text(blurb).textStyle(.body).foregroundStyle(Color.muted)
                        Text(example).textStyle(.label).foregroundStyle(Color.orange)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Space.md)
                    HRule()
                }
            }

            Text("Examples only — Hourss has not met you yet.")
                .textStyle(.label)
                .foregroundStyle(Color.muted)
        }
        .pageGutter()
        .padding(.top, Space.md)
    }
}

/// O3 — pick 1–3 intents.
private struct IntentStep: View {
    @Environment(HourssStore.self) private var store

    var body: some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: Space.lg) {
            Eyebrow("What brings you here")
            DisplayHeadline([
                Text("Pick up to").styled(.sectionTitle),
                Text("three.").styled(.emphasis(42)),
            ], style: .sectionTitle)

            VStack(spacing: 0) {
                HRule()
                ForEach(Intent.allCases) { intent in
                    let selected = store.profile.goals.contains(intent)
                    Button {
                        if selected {
                            store.profile.goals.remove(intent)
                        } else if store.profile.goals.count < 3 {
                            store.profile.goals.insert(intent)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: Space.sm) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(intent.title).textStyle(.stepName)
                                Text(intent.blurb).textStyle(.body).foregroundStyle(Color.muted)
                            }
                            Spacer(minLength: Space.sm)
                            Text(selected ? "●" : "○")
                                .font(.custom("DMSans-Medium", fixedSize: 14))
                                .foregroundStyle(selected ? Color.orange : Color.rule)
                                .padding(.top, 6)
                        }
                        .padding(.vertical, Space.sm)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                    HRule()
                }
            }

            Text("This shapes the language Hourss uses, not what it records.")
                .textStyle(.label)
                .foregroundStyle(Color.muted)
        }
        .pageGutter()
        .padding(.top, Space.md)
    }
}

/// O5 — the starter activity set.
private struct ActivitiesStep: View {
    @Environment(HourssStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Eyebrow("What fills your days")
            DisplayHeadline([
                Text("Keep what").styled(.sectionTitle),
                Text("you ").styled(.sectionTitle).then(Text("recognise.").styled(.emphasis(42))),
            ], style: .sectionTitle)

            VStack(spacing: 0) {
                HRule()
                ForEach(store.activities) { activity in
                    SelectableChip(title: activity.name, isSelected: activity.isFavorite) {
                        store.toggleFavorite(activity.id)
                    }
                }
            }

            Text(
                store.favoriteCount == 0
                    ? "Keep at least one — you can change these later."
                    : "You can add your own once you're in."
            )
            .textStyle(.label)
            .foregroundStyle(store.favoriteCount == 0 ? Color.orange : Color.muted)
        }
        .pageGutter()
        .padding(.top, Space.md)
    }
}

/// O9 — the shortest possible first log, or a way past it.
private struct FirstLogStep: View {
    @Environment(HourssStore.self) private var store
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Eyebrow("One log to start")
            DisplayHeadline([
                Text("What are you").styled(.sectionTitle),
                Text("doing ").styled(.sectionTitle).then(Text("now?").styled(.emphasis(42))),
            ], style: .sectionTitle)

            VStack(spacing: 0) {
                HRule()
                ForEach(store.pickableActivities.prefix(4)) { activity in
                    Button {
                        store.startSession(activityId: activity.id)
                        onFinish()
                    } label: {
                        HStack {
                            Text(activity.name).textStyle(.stepName)
                            Spacer()
                            Text("Start now").textStyle(.label).foregroundStyle(Color.orange)
                        }
                        .padding(.vertical, Space.sm)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    HRule()
                }
            }

            Button("Skip for now") { onFinish() }
                .buttonStyle(.plain)
                .textStyle(.action)
                .foregroundStyle(Color.muted)
                .frame(minHeight: Space.tapTarget)
        }
        .pageGutter()
        .padding(.top, Space.md)
    }
}
