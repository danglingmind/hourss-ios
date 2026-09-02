import SwiftUI

/// O1 → O9, minus the screens that need a real backend.
///
/// Notifications (O7) and account (O8) depend on the system notification sheet
/// and Clerk, so they are out of the shell rather than faked. Health (O6) is real:
/// it raises the genuine iOS sheet, and only after an explicit in-app tap.
struct OnboardingFlow: View {
    @Environment(HourssStore.self) private var store
    @State private var step = 0

    private let stepCount = 6

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
                        case 4: HealthStep(onDone: { step += 1 })
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
                if step < stepCount - 1 && step != 4 {
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
            // A day, drawn. It says "keeps a quiet record of how your time feels"
            // faster than the sentence that used to sit here.
            VStack(alignment: .leading, spacing: Space.xs) {
                SegmentStrip(segments: [
                    .init(weight: 3, color: .lime),
                    .init(weight: 1, color: .restorativeFill),
                    .init(weight: 2, color: .drainingFill),
                    .init(weight: 2, color: .lime),
                ])
                .frame(maxWidth: 300)
                .accessibilityLabel("An example day: energizing, then mixed, then draining, then energizing again")

                Text("Nothing to optimise. Nothing to score.")
                    .textStyle(.body)
                    .foregroundStyle(Color.mutedOnDark)
            }
            Spacer()
            Text("Your data stays yours.")
                .textStyle(.label)
                .foregroundStyle(Color.subtleOnDark)
        }
        .pageGutter()
        .padding(.vertical, Space.lg)
    }
}

/// O2 — three illustrative examples, drawn rather than described.
///
/// Each row used to carry a sentence explaining a kind of noticing. The marks say
/// it faster, and this screen is the one place in the app where drawn examples are
/// honest — the disclaimer underneath is doing that work, and must stay adjacent.
/// Patterns screens never draw anything the data has not earned.
private struct NoticeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Eyebrow("What Hourss notices")
            DisplayHeadline([
                Text("Three kinds").styled(.sectionTitle),
                Text("of ").styled(.sectionTitle).then(Text("noticing.").styled(.emphasis(42))),
            ], style: .sectionTitle)

            VStack(spacing: 0) {
                HRule()

                exampleRow("Timing", example: "Deep work before 11am") {
                    // Deliberately unlabelled with numbers. These are illustrations,
                    // and a printed "4.4" would read as a finding.
                    VStack(alignment: .leading, spacing: 3) {
                        DataBar(fraction: 0.85, height: 12)
                        DataBar(fraction: 0.45, fill: .rule, height: 12)
                    }
                    .accessibilityElement()
                    .accessibilityLabel("Example: one time of day rating higher than another")
                }

                exampleRow("Energy", example: "A walk without a podcast") {
                    SegmentStrip(segments: [
                        .init(weight: 3, color: .lime),
                        .init(weight: 2, color: .drainingFill),
                        .init(weight: 1, color: .restorativeFill),
                        .init(weight: 3, color: .lime),
                    ], height: 12)
                    .accessibilityLabel("Example: some activities give energy back, others take it")
                }

                exampleRow("Conditions", example: "After a longer night's sleep") {
                    CoverageMark(segments: [true, false, true, true, false, true, true], height: 12)
                        .accessibilityLabel("Example: the days a condition repeated on")
                }
            }

            Text("Examples only — Hourss has not met you yet.")
                .textStyle(.label)
                .foregroundStyle(Color.muted)
        }
        .pageGutter()
        .padding(.top, Space.md)
    }

    private func exampleRow<Mark: View>(
        _ name: String,
        example: String,
        @ViewBuilder mark: () -> Mark
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(name).textStyle(.body)
                mark()
                Text(example).textStyle(.label).foregroundStyle(Color.orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Space.sm)
            HRule()
        }
    }
}

/// O3 — pick 1–3 intents.
///
/// Each option used to carry a sentence restating its own one-word title. The
/// spec asks for chips, and chips are what a five-way choice needs.
private struct IntentStep: View {
    @Environment(HourssStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Eyebrow("What brings you here")
            DisplayHeadline([
                Text("Pick up to").styled(.sectionTitle),
                Text("three.").styled(.emphasis(42)),
            ], style: .sectionTitle)

            VStack(spacing: 0) {
                HRule()
                ForEach(Intent.allCases) { intent in
                    let selected = store.profile.goals.contains(intent)
                    SelectableChip(title: intent.title, isSelected: selected) {
                        if selected {
                            store.profile.goals.remove(intent)
                        } else if store.profile.goals.count < 3 {
                            store.profile.goals.insert(intent)
                        }
                    }
                }
            }

            Text("Shapes the language, not the record.")
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
                    SelectableChip(
                        title: activity.name,
                        isSelected: activity.isFavorite,
                        glyph: .forActivity(named: activity.name)
                    ) {
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

/// O6 — Apple Health, optional and granular.
///
/// The categories are individually selectable and each says what it unlocks,
/// because the spec requires the read scopes be explained *before* the OS dialog,
/// not after it. Declining is not a failure state and leads nowhere different —
/// "the app remains fully usable without Health."
private struct HealthStep: View {
    @Environment(HealthService.self) private var health
    @Environment(HourssStore.self) private var store
    let onDone: () -> Void

    @State private var isConnecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Eyebrow("Context, if you want it")
            DisplayHeadline([
                Text("What was going").styled(.sectionTitle),
                Text("on ").styled(.sectionTitle).then(Text("around it.").styled(.emphasis(42))),
            ], style: .sectionTitle)

            VStack(spacing: 0) {
                HRule()
                ForEach(HealthGroup.allCases) { group in
                    groupRow(group)
                }
            }

            Text("Read only. Hourss works fully without this.")
                .textStyle(.label)
                .foregroundStyle(Color.muted)

            HStack {
                Button("Not now") { onDone() }
                    .buttonStyle(.plain)
                    .textStyle(.action)
                    .foregroundStyle(Color.muted)
                    .frame(minHeight: Space.tapTarget)
                    .accessibilityIdentifier("health-skip")

                Spacer()

                DirectionalLink(title: "Connect Health", arrow: "→") {
                    isConnecting = true
                    Task {
                        await health.connect()
                        store.applyHealthContext(health.dailyValues)
                        isConnecting = false
                        onDone()
                    }
                }
                .disabled(health.selectedGroups.isEmpty || isConnecting)
                .accessibilityIdentifier("health-connect")
            }
        }
        .pageGutter()
        .padding(.top, Space.md)
    }

    /// Each group names the exact types it reads, so nothing is consented to
    /// blind — the acceptance test on granular access is that scope is displayed.
    private func groupRow(_ group: HealthGroup) -> some View {
        @Bindable var health = health
        let selected = health.selectedGroups.contains(group)

        return Button {
            if selected {
                health.selectedGroups.remove(group)
            } else {
                health.selectedGroups.insert(group)
            }
        } label: {
            HStack(alignment: .top, spacing: Space.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title).textStyle(.stepName)
                    Text(group.benefit)
                        .textStyle(.label)
                        .foregroundStyle(Color.muted)
                    Text(group.scopeDescription)
                        .textStyle(.label)
                        .foregroundStyle(Color.tertiaryOnCanvas)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.sm)
                Text(selected ? "●" : "○")
                    .font(.custom("DMSans-Medium", fixedSize: 14))
                    .foregroundStyle(selected ? Color.orange : Color.rule)
                    .padding(.top, 6)
            }
            .padding(.vertical, Space.sm)
            .frame(minHeight: Space.tapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("health-\(group.rawValue)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .overlay(alignment: .bottom) { HRule() }
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
