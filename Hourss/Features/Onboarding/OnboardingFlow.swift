import SwiftUI

/// Onboarding, as a nine-beat argument.
///
/// Problem → promise → priorities → key → mechanism → proof → account →
/// reminders → promo.
/// The proof beat is the
/// point of the whole sequence: real statistics computed from the person's own
/// Apple Health history, shown before they have logged a single thing.
///
/// That is also why the Health request sits at beat two rather than later. Reading
/// a year of history takes real seconds, so it starts there and runs behind the
/// key and mechanism screens — by the time the proof beat appears, it is already
/// computed. The narrative pays for the latency.
///
/// The account beat sits after the proof rather than before it, and that ordering
/// is the argument. Asked first, signing in is a toll on an app nobody has seen
/// yet; asked here, it comes directly after three true statements about this
/// person's own life, and what it secures is something they have just been shown.
///
/// It is also the one beat with no way past it. Every other screen here can be
/// continued through; this one advances only once Apple has answered.
///
/// The reminders beat sits second to last, immediately before the screen that asks
/// someone to log for the first time — so the question "how often should we ask?"
/// arrives next to the thing it is asking about. It states the cost of each choice
/// in notifications per day, and it is skippable: "Don't remind me" is a real
/// option on the list rather than a link hidden underneath it.
struct OnboardingFlow: View {
    @Environment(HourssStore.self) private var store
    @Environment(HealthService.self) private var health
    @Environment(AccountService.self) private var account
    @Environment(NotificationService.self) private var notifications

    @State private var step = 0
    @State private var digest = DigestState.idle
    @State private var isConnecting = false

    /// Starts on the recommendation rather than on nothing. "Recommended" that
    /// still needs a tap to take effect is a label, not a recommendation — and an
    /// unselected list would make Continue mean something different depending on
    /// whether the person noticed the rows.
    @State private var reminder = LogReminderFrequency.recommended
    @State private var isSchedulingReminders = false

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

    private let stepCount = 9

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
                        case 6: AccountStep()
                        case 7: ReminderStep(selection: $reminder)
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
            VStack(spacing: 0) {
                primaryAction
                    .padding(.top, Space.xs)
                // Under the way forward rather than beside it, so the filled
                // block spans the column and Back reads as the quieter of the
                // two rather than as its equal.
                if step > 0 && step != 1 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.plain)
                        .textStyle(.action)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Space.tapTarget)
                }
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
            PrimaryAction(title: isConnecting ? "Reading…" : "Connect Health") {
                isConnecting = true
                Task {
                    await health.connect()
                    isConnecting = false
                    connected()
                }
            }
            .disabled(isConnecting)
            .accessibilityIdentifier("health-connect")

        case 2:
            PrimaryAction(title: "Continue") { step += 1 }
                .disabled(store.profile.priorities.isEmpty)

        case 6:
            // The gate. Nothing at all on screen until Apple has answered, so
            // there is no control to mistake for a way around it — and the moment
            // it has, the ordinary Continue appears where the eye already is.
            if account.isSignedIn {
                PrimaryAction(title: "Continue") { step += 1 }
            } else {
                EmptyView()
            }

        case 7:
            // Doing the asking here rather than on the beat itself, so the system
            // prompt is raised by the same footer action every other beat uses —
            // and only ever after this screen has explained what it is for.
            PrimaryAction(title: isSchedulingReminders ? "Setting up…" : "Continue") {
                isSchedulingReminders = true
                Task {
                    store.profile.logReminder = reminder
                    store.persist()
                    await notifications.enableReminders(for: store.profile)
                    isSchedulingReminders = false
                    step += 1
                }
            }
            .disabled(isSchedulingReminders)

        case stepCount - 1:
            EmptyView()   // the last beat owns its own exits

        default:
            PrimaryAction(title: step == 0 ? "Start" : "Continue") { step += 1 }
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
            await applyHealthRead(from: health, to: store)
        }
    }

    private func finish() {
        store.hasCompletedOnboarding = true
        // Onboarding is the one place that writes the profile and the activity
        // list, and it writes them straight onto the store rather than through a
        // method, so this is where they reach the disk.
        store.persist()
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

            // Short on purpose. This page has to reach its button without a
            // scroll — that was reported once already and came straight back the
            // moment prose was added above the fold.
            Text("Your body has already kept the record. Hourss reads it, so day one starts with a year of evidence.")
                .textStyle(.body)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)

            // Was a list of four toggles. Every one of them had to be on for the
            // engine to say anything, so the choice was between using the app and
            // not — and a control whose only real setting is "yes" is a control
            // that exists to look generous. Stating what is read is honest;
            // pretending it is optional was not.
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("\(HealthMetric.allCases.count) signals · four groups")
                    .padding(.bottom, Space.xs)
                HRule()
                ForEach(HealthGroup.allCases) { group in
                    groupRow(group)
                }
            }

            Text("Read only. Nothing is ever written back, and nothing leaves your phone.")
                .textStyle(.label)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .pageGutter()
        .padding(.top, Space.md)
    }

    private func groupRow(_ group: HealthGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.title)
                .textStyle(.stepName)
            Text(group.scopeDescription)
                .textStyle(.label)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.sm)
        .overlay(alignment: .bottom) { HRule() }
        .accessibilityElement(children: .combine)
        // Kept from when these were buttons. The rows are no longer a choice,
        // but the screen still has to be addressable — what is on it is the
        // whole disclosure, and a disclosure nothing can assert against is one
        // nobody will notice going missing.
        .accessibilityIdentifier("health-\(group.rawValue)")
    }
}

// MARK: - 3 · Priorities

/// What you want to improve, in your own order.
///
/// The control itself is `PriorityRanker`, shared with Profile — where the promise
/// this screen makes at the bottom ("you can change this later") is kept.
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

            PriorityRanker(ranked: $store.profile.priorities, maximum: maximum)

            Text(store.profile.priorities.isEmpty
                 ? "Pick at least one — you can change this later."
                 : "You can change this later.")
                .textStyle(.label)
                .foregroundStyle(store.profile.priorities.isEmpty ? Color.orange : Color.muted)
        }
        .pageGutter()
        .padding(.top, Space.md)
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
                // "Reading" rather than naming the shape. The line survived the
                // bars becoming arcs only by accident; the claim it makes is
                // about how many things are being measured, not about what they
                // are drawn as.
                Text("There is no third reading. Hourss never compares you to anyone else.")
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
                        HealthFactRow(fact: fact, revealIndex: index, identifier: "proof-fact")
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
}

// MARK: - 7 · The account

/// The gate, and the only screen in onboarding with no way through it.
///
/// Placed here because of what is on the screen before it: the person has just
/// been shown three true things about their own life, computed from their own
/// history. Signing in is asked for against that, not against a promise.
///
/// The signed-in branch is not dead code. Deleting everything from Privacy & data
/// resets onboarding but deliberately leaves the account alone — deletion is about
/// the record, not about who somebody is — so the next run through arrives here
/// already signed in and must say so rather than asking again.
private struct AccountStep: View {
    @Environment(AccountService.self) private var account

    var body: some View {
        if let signedIn = account.account {
            VStack(alignment: .leading, spacing: Space.lg) {
                Eyebrow("Your account")

                // "Signed in" rather than "already signed in": this is also the
                // screen somebody lands on the instant they finish signing in on
                // it, and being told they had already done it reads as a fault.
                DisplayHeadline([
                    Text("Signed in").styled(.sectionTitle),
                    Text("with ").styled(.sectionTitle).then(Text("Apple.").styled(.emphasis(42))),
                ], style: .sectionTitle)

                Text(signedIn.fullName.map { "This record is down to \($0), and stays on this iPhone. Nothing about it is sent anywhere." }
                     ?? "This record is down to your Apple ID, and stays on this iPhone. Nothing about it is sent anywhere.")
                    .textStyle(.body)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .pageGutter()
            .padding(.top, Space.md)
            .accessibilityIdentifier("account-signed-in")
        } else {
            SignInPanel(
                headline: [
                    Text("One account,").styled(.sectionTitle),
                    Text("on this ").styled(.sectionTitle).then(Text("phone.").styled(.emphasis(42))),
                ],
                lead: "You have just seen what your own history already says. Signing in with Apple is what makes that record yours — it stays on this iPhone, and signing in sends none of it anywhere."
            )
            // Deliberately unidentified. `accessibilityIdentifier` propagates to
            // every descendant, so an identifier here overwrites the one on the
            // Apple button — the single control this screen exists for — and makes
            // it unfindable. The button's own identifier is what says the beat
            // arrived, and says it more precisely than a wrapper could.
        }
    }
}

// MARK: - 8 · Reminders

/// How often Hourss should ask what you are doing.
///
/// Placed immediately before the beat that asks for a first log, because that is
/// the thing being scheduled. Nothing is requested from iOS while this is on
/// screen — the system prompt is raised by Continue, after the choice is made and
/// after this screen has said what each choice costs.
private struct ReminderStep: View {
    @Binding var selection: LogReminderFrequency

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Eyebrow("Reminders")
            DisplayHeadline([
                Text("How often").styled(.sectionTitle),
                Text("should we ").styled(.sectionTitle).then(Text("ask?").styled(.emphasis(42))),
            ], style: .sectionTitle)

            Text("An hour is easiest to remember while it is still happening. Hourss can nudge you — tapping the nudge opens the list and nothing else.")
                .textStyle(.body)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)

            LogReminderPicker(selection: $selection)

            Text("Never overnight, and you can change or stop this at any time in You.")
                .textStyle(.label)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .pageGutter()
        .padding(.top, Space.md)
    }
}

// MARK: - 9 · The promo

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
