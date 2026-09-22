import SwiftUI

/// L3 — the end-of-session reflection.
///
/// Performance is optional and never blocks the save, and a note is never
/// required. Nothing here defaults to a middle value: an unanswered scale stays
/// unanswered.
///
/// **A feeling does not save the moment it is tapped.** This comment used to say
/// it did, and it has not been true since the card arrived: `save` and the sheet
/// header both route through `rate()`, which decides whether a card is owed
/// *before* anything is written, because `store.saveReflection` clears the very
/// binding this sheet is presented through and would tear the view down under
/// the card. So the rating lives in `@State` until `commit()`, which is what the
/// interactive-dismiss guard and the `onDisappear` fallback below are protecting.
/// The residual risk is a hard process kill while the card is up.
///
/// The first rating of each day also gets something back — see `DayContextCard`,
/// which this view raises over itself rather than presenting.
struct ReflectionView: View {
    @Environment(HourssStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let sessionId: UUID

    @State private var feeling: Int?
    @State private var performance: Int?
    @State private var note = ""

    /// The day's fact, once it has been earned. Held here rather than in the
    /// store because of the ordering problem described on `rate()`.
    @State private var card: DayContextCard.Content?
    @State private var hasSaved = false

    private var session: Session? { store.sessions.first { $0.id == sessionId } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Reflection", onClose: { finish() })

            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    if let session {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.activityName(session.activityId)).textStyle(.stepName)
                            Text("\(session.startAt.formatted(.dateTime.hour().minute())) · \(formatMinutes(session.durationMinutes))")
                                .textStyle(.label)
                                .foregroundStyle(Color.muted)
                        }
                    }

                    HRule()

                    RatingScale(value: $feeling, kind: .feeling)

                    // Performance stays on screen rather than behind a disclosure.
                    // It is still optional — nothing is preselected and the save
                    // path does not care whether it was answered.
                    VStack(alignment: .leading, spacing: Space.sm) {
                        HRule()
                        RatingScale(
                            value: $performance,
                            kind: .performance,
                            caption: "Optional — a different question."
                        )
                        .padding(.top, Space.xs)
                    }

                    VStack(alignment: .leading, spacing: Space.xs) {
                        Eyebrow("A note — optional")
                        TextField("Anything worth remembering?", text: $note, axis: .vertical)
                            .textStyle(.bodyLarge)
                            .tint(.orange)
                            .padding(.vertical, Space.sm)
                            .overlay(alignment: .bottom) { HRule(color: .ink) }
                    }
                }
                .pageGutter()
                .padding(.vertical, Space.md)
            }

            VStack(spacing: 0) {
                HRule()
                HStack {
                    Button("Skip") { dismiss() }
                        .buttonStyle(.plain)
                        .textStyle(.action)
                        .foregroundStyle(Color.muted)
                        .frame(minHeight: Space.tapTarget)
                    Spacer()
                    DirectionalLink(title: "Save", arrow: "→") { rate() }
                }
                .pageGutter()
            }
        }
        .surface(.canvas)
        // An overlay, not a sheet and not a second screen.
        //
        // `store.saveReflection` clears `pendingReflectionSessionId`, which *is*
        // the `.sheet(item:)` binding this view is presented through
        // (`RootView.swift:92`). Saving therefore tears this view down in the same
        // runloop pass, and anything presented *from* here goes with it. So the
        // card is drawn over the reflection inside the one sheet that is already
        // on screen, and the save is what waits instead — see `rate()`.
        .overlay {
            if let card {
                DayContextCard(content: card) { finish() }
                    .transition(.opacity)
            }
        }
        // While the card is up the rating is recorded in `@State` and nowhere
        // else. A swipe-down here would lose it, so there isn't one; the card's
        // own "Done" is the way out. `onDisappear` below is the belt to this
        // braces, for the dismissals iOS does not ask permission for.
        .interactiveDismissDisabled(card != nil)
        .onDisappear {
            if card != nil { commit() }
        }
        .onAppear {
            if let existing = store.reflection(for: sessionId) {
                feeling = existing.feelingScore
                performance = existing.performanceScore
                note = existing.note ?? ""
            }
        }
    }

    /// Save was tapped. Either the day owes a card, or this is over.
    ///
    /// The card is decided *before* the save rather than after it, and the save
    /// is deferred until the card is done with. That inversion is forced: the
    /// store clears the sheet's own binding as part of saving, so a card raised
    /// after a save would be raised onto a view that no longer exists.
    ///
    /// Three conditions, all necessary. A feeling must actually have been
    /// recorded — a Skip, or a save carrying only a note, has not rated anything
    /// and gets nothing back. It must be the first rating of the calendar day.
    /// And there must be something true to say, which most days there is not.
    ///
    /// Three things can be said, in this order: a milestone, then the day's
    /// standout, then the session's heart-rate residual. The order is by how
    /// rare each one is and how much of the record it speaks for — a milestone
    /// is a fact about everything logged so far, a standout about a whole day, a
    /// residual about one window of one afternoon. Whichever wins, only one is
    /// shown; `DayContextCard.Content` is an enum so that is not a matter of
    /// remembering.
    private func rate() {
        guard let feeling else {
            finish()
            return
        }

        // A milestone first, and not subject to the once-a-day gate.
        //
        // The gate exists so a card does not appear on every rating. A milestone
        // cannot: it requires a rating strictly above everything logged before
        // it, so on a five-point scale it is rare by construction and gets rarer
        // the longer somebody uses the app. Gating it would mean earning the one
        // moment the record can produce and then not being told, because a sleep
        // figure had already used the slot that morning.
        if let milestone = RatingMilestone.earned(
            by: sessionId,
            rating: feeling,
            sessions: store.sessions,
            feeling: { store.feeling(for: $0) },
            activityName: store.activityName
        ) {
            // Still marks the day, so a milestone in the morning does not leave a
            // health card to arrive in the afternoon. One card a day either way;
            // which one it is depends on what there was to say.
            store.markContextCardShown()
            card = .milestone(milestone)
            return
        }

        guard store.isContextCardDue else {
            finish()
            return
        }

        // The day's standout next. It is about the whole day, so it is the
        // wider claim of the two that remain, and a card is worth more the less
        // often it says something the person could have worked out themselves.
        if let standout = DayDeviation.standout(on: Date(), history: store.healthByDay) {
            // Claimed only now, with a card in hand. Claiming it at the guard
            // above would spend the day's one card on a day that had no fact in
            // it.
            store.markContextCardShown()
            card = .health(standout)
            return
        }

        // The session's own heart rate last, and it will almost never fire here.
        //
        // That is expected and is not a reason to move it earlier. watchOS hands
        // heart-rate samples to the phone opportunistically, so the window that
        // closed a minute ago usually holds nothing yet, and a reading also needs
        // a clean lead-in and a fitted curve before it exists at all. Where this
        // does fire is the case where the data has long since arrived: a
        // backdated log, or a rating given from the Journal days later. The
        // timeline's session detail is the surface that shows a residual
        // reliably — this is the one that shows it at the moment somebody is
        // already looking.
        //
        // `SessionResidual.init?` is the uncertainty gate. There is no second
        // check here because there is no way to build one of these without it.
        if let residual = SessionResidual(store.physiologyReadings[sessionId]) {
            store.markContextCardShown()
            card = .residual(residual)
            return
        }

        finish()
    }

    private func finish() {
        commit()
        dismiss()
    }

    /// Idempotent, because there are now two paths into it — the button and
    /// `onDisappear` — and the second one must not re-stamp a reflection the
    /// first one already wrote.
    private func commit() {
        guard !hasSaved else { return }
        hasSaved = true
        store.saveReflection(sessionId: sessionId, feeling: feeling, performance: performance, note: note)
    }
}
