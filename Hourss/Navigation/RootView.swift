import SwiftUI

/// Onboarding gates the tabs; after that the app is the four destinations from the
/// spec plus the centred log action.
///
/// Three things can stand in front of the tabs, and the order below is the order
/// they are answered in. Onboarding first, because it is where an account is
/// asked for in the first place and a gate in front of it would ask twice. Then
/// the account, because a withdrawn credential means nobody has said this record
/// may be opened. Then Health, because everything behind it is built from readings
/// that have stopped arriving.
struct RootView: View {
    @Environment(HourssStore.self) private var store
    @State private var selection: Tab = .today
    @State private var isStartingSession = false

    @Environment(HealthService.self) private var health
    @Environment(AccountService.self) private var account
    @Environment(NotificationService.self) private var notifications
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var store = store

        Group {
            if !store.hasCompletedOnboarding {
                OnboardingFlow()
                    .transition(.opacity)
            } else if account.isChecking {
                // Deliberately neither screen. Asking Apple is quick but not
                // instant, and both guesses are wrong in a way somebody sees.
                AccountCheckView()
                    .transition(.opacity)
            } else if !account.isSignedIn {
                AccountGateView()
                    .transition(.opacity)
            } else if health.accessLost {
                // Ahead of the app rather than over it. Every screen behind this
                // is built from readings that are no longer arriving, so leaving
                // them reachable would mean showing somebody a feed that has
                // quietly stopped being true.
                ReconnectHealthView()
                    .transition(.opacity)
            } else {
                main
            }
        }
        .animation(.easeOut(duration: Motion.standard), value: store.hasCompletedOnboarding)
        .animation(.easeOut(duration: Motion.standard), value: account.state)
        .animation(.easeOut(duration: Motion.standard), value: health.accessLost)
    }

    private var main: some View {
        @Bindable var store = store

        return VStack(spacing: 0) {
            ZStack {
                switch selection {
                case .today: NavigationStack { TodayView(onLog: startLogging).enablesSwipeBack() }
                case .patterns: NavigationStack { PatternsView().enablesSwipeBack() }
                case .journal: NavigationStack { JournalView().enablesSwipeBack() }
                case .you: NavigationStack { YouView().enablesSwipeBack() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // A cross-fade, which is what the system's own tab bar does — it does
            // not slide, and a slide here would be wrong twice over: there is no
            // spatial relationship between Patterns and Journal to honour, and the
            // `+` sits between them, so a directional transition would have to
            // decide which side of a button that is not a tab each screen lives
            // on. Four screens swapped with no transition at all read as the app
            // reloading; a dissolve reads as one surface changing what it shows.
            //
            // The rule underneath is already travelling on its own spring, so the
            // two are deliberately different gestures: the rule tells you *which*
            // tab you moved to while the content tells you it changed.
            .animation(Motion.content(reduced: reduceMotion), value: selection)

            EditorialTabBar(selection: $selection, onLog: startLogging)
        }
        .background(Color.canvas)
        .onOpenURL { url in
            // Opened from the Live Activity. Today is where a session that just
            // ended actually shows up.
            if url.scheme == "hourss" { selection = .today }
        }
        // A tapped reminder goes straight to the activity list — the same sheet
        // the + button opens, because the notification asked the same question.
        //
        // `initial: true` is doing real work: a tap that launches the app cold
        // sets this before any of this view exists, and a plain change handler
        // would never see the value it was already holding. The gates in front of
        // `main` are why it can arrive early — onboarding, the account check and
        // the Health screen all sit between launch and here.
        .onChange(of: notifications.pendingLogRequest, initial: true) { _, request in
            guard request != nil else { return }
            isStartingSession = true
            notifications.consumeLogRequest()
        }
        // An empty hour tapped in a day's hour strip raises the same sheet the +
        // button does. The slot itself travels on the store; this only has to
        // know that something asked.
        .onChange(of: store.pendingLogSlot) { _, slot in
            guard slot != nil else { return }
            isStartingSession = true
        }
        .sheet(isPresented: $isStartingSession) {
            StartSessionView()
                .presentationCornerRadius(0)
        }
        // A session ending anywhere in the app raises the same reflection sheet.
        .sheet(item: Binding(
            get: { store.pendingReflectionSessionId.map(IdentifiedUUID.init) },
            set: { if $0 == nil { store.pendingReflectionSessionId = nil } }
        )) { wrapper in
            ReflectionView(sessionId: wrapper.id)
                .presentationCornerRadius(0)
        }
    }

    /// The tab bar's `+` is the log action, nothing else.
    ///
    /// It used to double as a stop button while a session ran, which made
    /// backdating impossible mid-session — the one time you are most likely to be
    /// catching up on a forgotten hour. Stopping already has a home on Today's
    /// active-session panel, where it reads unambiguously.
    private func startLogging() {
        isStartingSession = true
    }
}

/// `sheet(item:)` needs an `Identifiable`; `UUID` alone will not do.
struct IdentifiedUUID: Identifiable {
    let id: UUID
    init(_ id: UUID) { self.id = id }
}
