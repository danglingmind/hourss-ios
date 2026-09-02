import SwiftUI

/// Onboarding gates the tabs; after that the app is the four destinations from the
/// spec plus the centred log action.
struct RootView: View {
    @Environment(HourssStore.self) private var store
    @State private var selection: Tab = .today
    @State private var isStartingSession = false

    var body: some View {
        @Bindable var store = store

        Group {
            if store.hasCompletedOnboarding {
                main
            } else {
                OnboardingFlow()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: Motion.standard), value: store.hasCompletedOnboarding)
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

            EditorialTabBar(selection: $selection, onLog: startLogging)
        }
        .background(Color.canvas)
        .onOpenURL { url in
            // Opened from the Live Activity. Today is where a session that just
            // ended actually shows up.
            if url.scheme == "hourss" { selection = .today }
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
