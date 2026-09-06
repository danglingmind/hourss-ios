import SwiftUI

/// Onboarding, as a six-beat argument.
///
/// Problem → promise → key → mechanism → proof → promo. The proof beat is the
/// point of the whole sequence: real statistics computed from the person's own
/// Apple Health history, shown before they have logged a single thing.
///
/// That is also why the Health request sits at beat two rather than later. Reading
/// a year of history takes real seconds, so it starts there and runs behind the
/// key and mechanism screens — by the time the proof beat appears, it is already
/// computed. The narrative pays for the latency.
///
/// Notifications (O7) and account (O8) remain out of the shell: they need the
/// system notification sheet and Clerk, and a faked permission screen would teach
/// the wrong thing.
struct OnboardingFlow: View {
    @Environment(HourssStore.self) private var store
    @Environment(HealthService.self) private var health

    @State private var step = 0
    @State private var digest = DigestState.idle
    @State private var isConnecting = false

    /// Where the proof beat's data has got to.
    ///
    /// A plain optional could not tell "still reading" from "read, and there was
    /// nothing" — so anyone who reached beat five before the read finished was
    /// shown the honest empty state for data that was still on its way.
    enum DigestState {
        case idle
        case computing
        case ready(HealthDigest)
    }

    private let stepCount = 7

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { geo in
                ScrollView {
                    Group {
                        switch step {
                        case 0: ProblemStep()
                        case 1: PromiseStep()
                        case 2: PriorityStep()
                        case 3: KeyStep()
                        case 4: MechanismStep()
                        case 5: ProofStep(state: digest)
                        default: StartStep(onFinish: finish)
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
                if step > 0 && step != 1 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.plain)
                        .textStyle(.action)
                        .frame(minHeight: Space.tapTarget)
                }
                Spacer()
                primaryAction
            }
            .pageGutter()
            .padding(.bottom, Space.xs)
        }
    }

    /// Every beat's action lives here, pinned, including the Health ask.
    ///
    /// The ask used to carry its own button inside the scroll view, which meant
    /// shrinking its type until the button fitted on screen. Pinning it to the
    /// footer is what the rest of the flow already does, and it lets the content
    /// keep its proper size and scroll if it needs to.
    @ViewBuilder
    private var primaryAction: some View {
        switch step {
        case 1:
            DirectionalLink(title: isConnecting ? "Reading…" : "Connect Health", arrow: "→") {
                isConnecting = true
                Task {
                    await health.connect()
                    isConnecting = false
                    connected()
                }
            }
            .disabled(health.selectedGroups.isEmpty || isConnecting)
            .accessibilityIdentifier("health-connect")

        case 2:
            DirectionalLink(title: "Continue", arrow: "→") { step += 1 }
                .disabled(store.profile.priorities.isEmpty)

        case stepCount - 1:
            EmptyView()   // the last beat owns its own exits

        default:
            DirectionalLink(title: step == 0 ? "Start" : "Continue", arrow: "→") { step += 1 }
        }
    }

    /// Health has been asked for. Move on immediately and let the read finish
    /// behind the next two screens; the proof beat waits on `digest`.
    private func connected() {
        step += 1
        digest = .computing
        Task {
            await health.refresh()
            digest = .ready(HealthDigest.build(from: health.dailyValues))
            // Only now, once values actually exist. Doing this straight after
            // `connect()` used to run against an empty dictionary.
            store.applyHealthContext(health.dailyValues)
            store.applyPhysiology(feed: await health.readPhysiology())
        }
    }

    private func finish() {
        store.hasCompletedOnboarding = true
    }
}

// MARK: - 1 · The human problem

/// The one dark screen, and the app's own landing-page headline — so Hourss opens
/// in the voice it already speaks in.
private struct ProblemStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Spacer()
            Eyebrow("Where the hours go")
            DisplayHeadline([
                Text("Your calendar").styled(.display),
                Text("knows where").styled(.display),
                Text("time ").styled(.display).then(Text("went.").styled(.emphasis(58))),
            ])

            VStack(alignment: .leading, spacing: Space.sm) {
                SegmentStrip(segments: [
                    .init(weight: 3, color: .lime),
                    .init(weight: 1, color: .restorativeFill),
                    .init(weight: 2, color: .drainingFill),
                    .init(weight: 2, color: .lime),
                ])
                .frame(maxWidth: 300)
                .accessibilityLabel("A day: energizing, then mixed, then draining, then energizing again")

                Text("Nothing knows what it did to you.")
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

// MARK: - 2 · The promise, and the ask

/// The ask is the promise. Hourss can only start with what you have lived if it is
/// allowed to read what your body already recorded — so the two arrive together,
/// and there is no way past this screen but through it.
private struct PromiseStep: View {
    @Environment(HealthService.self) private var health

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Eyebrow("What Hourss does")
            DisplayHeadline([
                Text("Learn which hours").styled(.sectionTitle),
                Text("are worth ").styled(.sectionTitle).then(Text("keeping.").styled(.emphasis(42))),
            ], style: .sectionTitle)

            Text("Hourss starts with what you've already lived, not a blank page.")
                .textStyle(.body)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                HRule()
                ForEach(HealthGroup.allCases) { group in
                    groupRow(group)
                }
            }

            Text("Read only. Nothing is ever written back.")
                .textStyle(.label)
                .foregroundStyle(Color.muted)
        }
        .pageGutter()
        .padding(.top, Space.md)
    }

    /// Full size again. Shrinking the type to squeeze a button on screen was the
    /// wrong trade — the action belongs in the footer, and the content can breathe.
    /// The group name drops to body size and the row loses its generous padding —
    /// four rows at `stepName` plus their scope lines is what pushed the button
    /// off the screen.
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
                    Text(group.title)
                        .textStyle(.stepName)
                    Text(group.scopeDescription)
                        .textStyle(.label)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.sm)
                SelectionDot(isSelected: selected)
                    .padding(.top, 6)
            }
            .padding(.vertical, Space.sm)
            .frame(minHeight: Space.tapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("health-\(group.rawValue)")
        .accessibilityLabel("\(group.title). Reads \(group.scopeDescription)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .overlay(alignment: .bottom) { HRule() }
    }
}

// MARK: - 3 · Priorities

/// What you want to improve, in your own order.
///
/// Ranked by tapping in sequence rather than by dragging: reordering needs a
/// `List`, which brings the rounded, inset chrome this system exists without, and
/// a drag handle is a poor target on a first run. Tapping in order says the same
/// thing and can be undone by tapping again.
///
/// The order is not decoration. It weights which observations surface first, so a
/// stated priority changes the product rather than sitting in a profile.
private struct PriorityStep: View {
    @Environment(HourssStore.self) private var store

    private let maximum = 3

    var body: some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: Space.lg) {
            Eyebrow("What matters most")
            DisplayHeadline([
                Text("What would you").styled(.sectionTitle),
                Text("most like to ").styled(.sectionTitle).then(Text("change?").styled(.emphasis(42))),
            ], style: .sectionTitle)

            Text("Tap up to three, in order. Hourss will lead with what you put first.")
                .textStyle(.body)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                HRule()
                ForEach(Priority.allCases) { priority in
                    row(priority)
                }
            }

            Text(store.profile.priorities.isEmpty
                 ? "Pick at least one — you can change this later."
                 : "You can change this later.")
                .textStyle(.label)
                .foregroundStyle(store.profile.priorities.isEmpty ? Color.orange : Color.muted)
        }
        .pageGutter()
        .padding(.top, Space.md)
    }

    private func row(_ priority: Priority) -> some View {
        @Bindable var store = store
        let rank = store.profile.priorities.firstIndex(of: priority)

        return Button {
            toggle(priority)
        } label: {
            HStack(alignment: .top, spacing: Space.sm) {
                // The rank number is the whole interaction, so it carries the
                // accent and holds its column whether filled or not.
                Text(rank.map { "\($0 + 1)" } ?? "—")
                    .textStyle(.stepName)
                    .foregroundStyle(rank == nil ? Color.rule : Color.orange)
                    .frame(width: 28, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(priority.title).textStyle(.stepName)
                    Text(priority.basis)
                        .textStyle(.label)
                        .foregroundStyle(Color.muted)
                }
                Spacer(minLength: Space.sm)
            }
            .padding(.vertical, Space.sm)
            .frame(minHeight: Space.tapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("priority-\(priority.rawValue)")
        .accessibilityLabel(rank.map { "\(priority.title), ranked \($0 + 1). \(priority.basis)" }
                            ?? "\(priority.title), not ranked. \(priority.basis)")
        .accessibilityAddTraits(rank != nil ? [.isSelected] : [])
        .overlay(alignment: .bottom) { HRule() }
    }

    /// Tapping a ranked item removes it and closes the gap, so the numbers stay
    /// 1, 2, 3 rather than leaving a hole.
    private func toggle(_ priority: Priority) {
        if let index = store.profile.priorities.firstIndex(of: priority) {
            store.profile.priorities.remove(at: index)
        } else if store.profile.priorities.count < maximum {
            store.profile.priorities.append(priority)
        }
    }
}

// MARK: - 4 · The key

/// What actually makes this different from every other tracker: there is no third
/// bar. Both bars are you.
private struct KeyStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Eyebrow("The difference")
            DisplayHeadline([
                Text("Compared").styled(.sectionTitle),
                Text("only ").styled(.sectionTitle).then(Text("to you.").styled(.emphasis(42))),
            ], style: .sectionTitle)

            Text("No targets. No averages from strangers. Every observation measures you against your own history.")
                .textStyle(.body)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Space.sm) {
                HRule()
                Eyebrow("Your own baseline")
                ComparisonMark(
                    rows: [
                        .init(label: "Your better weeks", value: 4.3, count: nil, highlighted: true),
                        .init(label: "Your usual", value: 3.4, count: nil, highlighted: false),
                    ],
                    title: "Comparison against your own history"
                )
                Text("There is no third bar. Hourss never compares you to anyone else.")
                    .textStyle(.label)
                    .foregroundStyle(Color.muted)
            }
        }
        .pageGutter()
        .padding(.top, Space.md)
    }
}

// MARK: - 5 · The mechanism

private struct MechanismStep: View {
    private let steps: [(ActivityGlyph.Kind, String, String)] = [
        (.deepWork, "Start", "One tap when you begin."),
        (.rest, "Stop", "One tap when you're done."),
        (.creative, "How did that feel?", "One answer, one to five."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Eyebrow("How it works")
            DisplayHeadline([
                Text("One tap.").styled(.sectionTitle),
                Text("One ").styled(.sectionTitle).then(Text("question.").styled(.emphasis(42))),
            ], style: .sectionTitle)

            VStack(spacing: 0) {
                HRule()
                ForEach(Array(steps.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: Space.sm) {
                        ActivityGlyph(kind: item.0, size: 16, color: .ink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.1).textStyle(.stepName)
                            Text(item.2).textStyle(.label).foregroundStyle(Color.muted)
                        }
                        Spacer()
                    }
                    .padding(.vertical, Space.sm)
                    .frame(minHeight: Space.tapTarget)
                    HRule()
                }
            }

            Text("A log takes under five seconds. Everything else, Hourss works out.")
                .textStyle(.label)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .pageGutter()
        .padding(.top, Space.md)
    }
}

// MARK: - 6 · The proof

/// The payoff: three things already true about this person, computed from their
/// own Health history.
///
/// When there is nothing to read — no history, or a permission we were never told
/// about, which are indistinguishable — this says so plainly. Inventing numbers
/// here would make the one honest moment in onboarding the dishonest one.
private struct ProofStep: View {
    let state: OnboardingFlow.DigestState

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Eyebrow("Already true about you")

            if case .ready(let digest) = state, !digest.isEmpty {
                DisplayHeadline([
                    Text("\(digest.daysOfHistory) days,").styled(.sectionTitle),
                    Text("already ").styled(.sectionTitle).then(Text("read.").styled(.emphasis(42))),
                ], style: .sectionTitle)

                VStack(spacing: 0) {
                    HRule()
                    ForEach(Array(digest.facts.enumerated()), id: \.element.id) { index, fact in
                        factRow(fact, index: index)
                    }
                }

                Text("From your Health history. You haven't logged anything yet.")
                    .textStyle(.label)
                    .foregroundStyle(Color.muted)
            } else if case .ready = state {
                DisplayHeadline([
                    Text("Nothing to").styled(.sectionTitle),
                    Text("read ").styled(.sectionTitle).then(Text("yet.").styled(.emphasis(42))),
                ], style: .sectionTitle)

                Text("There isn't enough in Apple Health for Hourss to find anything worth showing. That changes as your watch records more — and none of it is needed for logging.")
                    .textStyle(.body)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("proof-empty")
            } else {
                DisplayHeadline([
                    Text("Reading your").styled(.sectionTitle),
                    Text("history…").styled(.emphasis(42)),
                ], style: .sectionTitle)
                .accessibilityIdentifier("proof-loading")
            }
        }
        .pageGutter()
        .padding(.top, Space.md)
    }

    private func factRow(_ fact: HealthDigest.Fact, index: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(fact.figure)
                    .textStyle(.dayNumeral)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(fact.sentence)
                    .textStyle(.body)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Only the mark draws in. Wiping the sentence too would make the
            // screen feel like it was loading rather than like it was showing you
            // something.
            mark(for: fact)
                .revealsOnAppear(index: index)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.md)
        .overlay(alignment: .bottom) { HRule() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(fact.sentence)
        .accessibilityIdentifier("proof-fact")
    }

    /// Lime at this person's high end, rule at their low end.
    private func rhythmColor(_ normalised: Double) -> Color {
        switch normalised {
        case ..<0.34: .rule
        case ..<0.67: .restorativeFill
        default: .lime
        }
    }

    @ViewBuilder
    private func mark(for fact: HealthDigest.Fact) -> some View {
        switch fact.mark {
        case .weekdayRhythm(let values):
            // Equal widths, varying colour. Weighting the widths compressed the
            // week into seven near-identical blocks; the extremes carry it better.
            HStack(spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Rectangle()
                        .fill(rhythmColor(value))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 16)
        case .comparison(let highLabel, let high, let lowLabel, let low):
            ComparisonMark(
                rows: [
                    .init(label: highLabel, value: high, count: nil, highlighted: true),
                    .init(label: lowLabel, value: low, count: nil, highlighted: false),
                ],
                scaleMax: max(high, low) * 1.15,
                unit: "",
                title: "Comparison"
            )
        case .none:
            EmptyView()
        }
    }
}

// MARK: - 7 · The promo

/// Start. The activity starter set folds in here, because picking what you are
/// doing right now is the same gesture as choosing which activities you keep.
private struct StartStep: View {
    @Environment(HourssStore.self) private var store
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Eyebrow("Start")
            DisplayHeadline([
                Text("Pick what").styled(.sectionTitle),
                Text("you're ").styled(.sectionTitle).then(Text("doing now.").styled(.emphasis(42))),
            ], style: .sectionTitle)

            VStack(spacing: 0) {
                HRule()
                ForEach(store.pickableActivities) { activity in
                    SelectableChip(
                        title: activity.name,
                        isSelected: false,
                        glyph: .forActivity(named: activity.name)
                    ) {
                        store.startSession(activityId: activity.id)
                        onFinish()
                    }
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
