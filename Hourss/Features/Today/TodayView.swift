import SwiftUI

/// T1, T2 and T3 are one screen in three states, driven by what the store holds:
/// nothing logged yet, a session running, or a day with a record.
struct TodayView: View {
    @Environment(HourssStore.self) private var store
    let onLog: () -> Void

    @State private var selectedSessionId: UUID?

    /// The recommendation layer's output, cached.
    ///
    /// Held here rather than read from the store because building it runs the
    /// engine — findings, the correction, the bootstrap — and a view body is
    /// re-evaluated on every keystroke elsewhere in the app. Recomputed when the
    /// record it rests on changes, and no more often.
    @State private var recommendations: [Recommendation] = []

    /// Proposals, cached for the same reason and on the same key: building them runs
    /// the engine and the correction before there is anything to offer.
    @State private var proposals: [ExperimentDesign.Proposal] = []

    /// How much of a running window has happened, cached because reading one
    /// resamples two thousand times.
    @State private var activeReading: ExperimentOutcome.Reading?

    /// Today's one fact from this person's own Health history, or nil.
    ///
    /// Deliberately a sibling of the observation slot rather than another case
    /// inside it. The slot is engine output gated on logged evidence, and its
    /// precedence table would let a fact outrank the unfinished-reflection
    /// prompt — the only route from this screen to rating a session that was
    /// actually logged. A fact costs nothing to show and must never be able to
    /// cost that.
    ///
    /// Cached here for the same reason the recommendations are: resolving it runs
    /// the four digest generators across a year of history, and a view body is
    /// re-evaluated far more often than a year of history changes.
    @State private var dailyFact: HealthDigest.Fact?

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var todaysSessions: [Session] { store.sessions(on: today) }

    var body: some View {
        ScrollView {
            // Two levels, so the indicator can sit close to what follows it without
            // moving any of the gaps below. A single VStack spaces every child
            // identically, and the day's heading is the one child that is metadata
            // rather than a section — it belongs to the screen, not beside the
            // section that happens to follow it. Space.xs here against Space.lg
            // everywhere else.
            VStack(alignment: .leading, spacing: 0) {
                dateHeading
                    .padding(.bottom, Space.xs)

                VStack(alignment: .leading, spacing: Space.lg) {
                    if let running = store.runningSession {
                        ActiveSessionPanel(session: running)          // T2
                    }

                    if todaysSessions.isEmpty {
                        emptyState                                     // T1
                    } else {
                        DayTimeline(                                   // T3
                            sessions: todaysSessions,
                            day: today,
                            selectedSessionId: $selectedSessionId
                        )
                    }

                    // Outside both branches, for the reason the daily fact below it
                    // is outside them — and it took an experiment settling overnight
                    // to notice. The slot used to sit inside the logged branch, so a
                    // finished test was invisible on any day nothing had been logged
                    // yet, which is both the likeliest morning to open the app and
                    // the one where a fortnight's result is the only thing it has to
                    // say. The slot renders nothing for `.none`, so a day with
                    // genuinely nothing to show is unchanged.
                    ObservationSlotView(
                        state: store.slotState(on: today,
                                               recommendations: recommendations,
                                               proposals: proposals),
                        recommendations: recommendations,
                        proposals: proposals,
                        activeReading: activeReading,
                        daysRemaining: store.activeExperiment?.daysRemaining(at: today) ?? 0,
                        // The day this screen is drawing, read once at the top of the
                        // body rather than again inside the copy layer.
                        now: today
                    )

                    // Last, and still outside both branches.
                    //
                    // **It is not gated, and that has not changed.** The whole point
                    // of the daily fact is that it costs nothing: it is already true
                    // about this person and needs no session, no rating and no
                    // streak. Putting it *inside* the logged branch would make the
                    // one thing here that asks nothing of them available only to
                    // people who had already given something, so it stays a sibling
                    // of both branches and shows on a day with an empty record
                    // exactly as it did before.
                    //
                    // **What changed is the order, and the order was never the
                    // gate.** This used to sit directly under the date, above both
                    // the day's own record and the test — so the first thing on the
                    // screen was the quietest thing the app has to say, and the test
                    // somebody had agreed to was below it. The order now is the
                    // date, then the day they are actually having, then the test,
                    // then this. The test is what the app is for and the one thing
                    // here anybody committed to; the fact is the thing you find once
                    // you have read the rest, which is the right weight for
                    // something that asks nothing and promises nothing.
                    dailyFactRow
                }
            }
            .pageGutter()
            .padding(.bottom, Space.xl)
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .navigationDestination(for: AllFactsRoute.self) { _ in AllFactsView() }
        .onAppear {
            if selectedSessionId == nil { selectedSessionId = todaysSessions.last?.id }
        }
        // The layer runs whether or not this person can see its output: the
        // upgrade prompt names how many recommendations they would get, so the
        // count only exists if the count was computed.
        .task(id: recommendationInputs) {
            // One engine run for both. Calling the two layers separately tested
            // sixty hypotheses at two thousand resamples twice, for two answers
            // derived from the same findings.
            let output = store.slotOutput()
            recommendations = output.recommendations
            proposals = output.proposals
            activeReading = store.activeExperiment.map { store.reading(for: $0) }
        }
        // The dispenser decides whether this is a day that spends a fact; asking
        // it more than once a day is free, which is why the whole of its memory
        // sits in defaults rather than in this view's lifetime.
        .task(id: dailyFactInputs) {
            dailyFact = DailyFact().fact(
                for: today,
                record: RecordFacts.pool(sessions: store.sessions,
                                         feeling: { store.feeling(for: $0) },
                                         activityName: store.activityName),
                from: HealthDigest.pool(from: store.healthByDay))
        }
    }

    /// The fact, when there is one. No empty state and no placeholder: a day with
    /// nothing left to say is a day this row does not exist, which is quieter than
    /// a box explaining its own absence and is the only honest shape once the
    /// pool runs out.
    @ViewBuilder
    private var dailyFactRow: some View {
        if let fact = dailyFact {
            // No rule above the fact, and the move down did not create a need for
            // one. It used to separate the fact from the day's heading, which was
            // two lines at 34pt and needed separating from; the heading became a
            // single line of 11pt mono, so the rule was ruling off a strip of
            // metadata from the thing it belongs to and went. What now sits above
            // the fact is the observation slot, which closes itself — a forest block
            // when it is carded, a ruled band when it is not — and `HealthFactRow`
            // draws its own rule along its bottom edge. A rule added here would be a
            // second line against one of those, which is the same mistake in a new
            // place.
            VStack(alignment: .leading, spacing: 0) {
                HealthFactRow(fact: fact, identifier: "today-fact")

                // Under the fact rather than beside it. The one-a-day pacing is
                // the default because it is what keeps the first week from being
                // silent, but it is a courtesy and not a lock, and somebody who
                // wants the whole list is asking about their own history.
                NavigationLink(value: AllFactsRoute()) {
                    HStack(spacing: 6) {
                        Text("View all").textStyle(.action)
                        Text("↘").font(.custom("DMSans-Bold", fixedSize: 18)).foregroundStyle(Color.orange)
                    }
                    .frame(minHeight: Space.tapTarget)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("view-all-facts")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            // The date used to sit opposite the wordmark and was the second of two:
            // the heading below already names the day, in full and in words, so the
            // corner was spending the most valuable position on the screen on a
            // thing the reader meets again four lines later.
            //
            // It holds the log action now. That argument is why this corner was
            // empty and free to take it — and the three other tabs have since given
            // up their own duplicate for the same reason, so every screen's `+` is
            // in the same place.
            HStack {
                Wordmark()
                Spacer()
                LogButton(action: onLog)
            }
            .pageGutter()
            .padding(.vertical, Space.gutter)
            HRule()
            runningTestStrip
        }
        .background(Color.canvas)
    }

    /// Whether today carries the change, for colour only.
    ///
    /// The sentence itself comes from `ExperimentCopy`; this asks the same question
    /// of the same assignment rather than trying to read the answer back out of the
    /// string, which would be two sources for one fact and would break the moment
    /// the wording changed.
    private func isTodayPicked(_ experiment: Experiment) -> Bool {
        guard let assignment = experiment.assignment,
              let offset = assignment.dayOffset(of: today, startedAt: experiment.startedAt,
                                                windowDays: experiment.windowDays)
        else { return false }
        return assignment.isAssigned(dayOffset: offset)
    }

    /// A test in progress, pinned where it cannot be missed.
    ///
    /// **The one thing somebody agreed to do should not be a thing they have to go
    /// and find.** It was a card below the fold on a screen that scrolls, so on a
    /// day with a few sessions logged it was off screen — and a test you forget
    /// about is a test that settles as "not enough to tell" a fortnight later. The
    /// header is the only part of this screen that is always visible.
    ///
    /// For a drawn window it says whether today is one of the picked days, which is
    /// the piece that makes one followable at all: a standing instruction fits in
    /// somebody's head for two weeks, and fourteen dates do not.
    ///
    /// **Nothing when nothing is running.** A header with an empty state in it is a
    /// header that has stopped being a header, and this screen already has somewhere
    /// to say that no test is on — the slot below, which offers one.
    ///
    /// Deliberately not a second copy of the active card. It carries the change and
    /// today's state and stops; the card below still owns the counts, the day list
    /// and the control to stop. Two renderings of one thing is how they drift.
    @ViewBuilder
    private var runningTestStrip: some View {
        if let experiment = store.activeExperiment {
            VStack(alignment: .leading, spacing: 2) {
                Text(experiment.change)
                    .textStyle(.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let line = ExperimentCopy.today(for: experiment, on: today) {
                    // Orange only when there is something to do today.
                    //
                    // Orange is this app's one signal colour — the now-line on the
                    // hour strip, the arrow on a link. Painting "today is *not* one
                    // of your days" with it spends the loudest thing on the screen
                    // drawing attention to a day somebody is meant to leave alone,
                    // which is both wrong and tiring on the half of a drawn window
                    // that asks for nothing.
                    Text(line)
                        .textStyle(.label)
                        .foregroundStyle(isTodayPicked(experiment) ? Color.orange : Color.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pageGutter()
            .padding(.vertical, Space.xs)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("running-test-strip")
            HRule()
        }
    }

    /// The day, as an indicator rather than a headline.
    ///
    /// **It used to be two lines at 34pt**, which on a phone is most of what you see
    /// before scrolling — and what it was telling you is what day it is, which is
    /// the one thing a reader already knows for certain. It is now `label`: the
    /// 11pt mono this app uses for metadata everywhere else, which is what this is.
    /// The weight it was holding belongs to the fact and the day's record below it.
    ///
    /// The date is not dropped altogether, because removing it from the header left
    /// this as the only place it appears. It just stops competing.
    ///
    /// Date and summary share one line, separated by a middle dot, because two
    /// stacked lines of the same 11pt mono read as a block of metadata rather than
    /// as one quiet marker. It wraps rather than truncating at large type sizes.
    ///
    /// **One clock read, not three.** These used to call `Date()` separately while
    /// `today` sat in scope — harmless for display, and the same shape as the bug
    /// that put the log-time preset fifteen minutes out roughly half the time. There
    /// is no reason for a view to ask what day it is more than once.
    private var dateHeading: some View {
        let date = today.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let line = todaysSessions.isEmpty
            ? date
            : "\(date) · \(daySummary(minutes: store.totalLoggedMinutes(on: today), sessionCount: todaysSessions.count))"

        return Text(line)
            .textStyle(.label)
            .foregroundStyle(Color.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Space.md)
    }

    /// T1 — nothing logged yet. An invitation, not an empty-state illustration.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HRule()
            DisplayHeadline([
                Text("Nothing logged").styled(.sectionTitle),
                Text("yet ").styled(.sectionTitle).then(Text("today.").styled(.emphasis(42))),
            ], style: .sectionTitle)
            .padding(.top, Space.sm)

            Text("Whatever you're doing right now is enough.")
                .textStyle(.body)
                .foregroundStyle(Color.muted)
                .frame(maxWidth: 320, alignment: .leading)

            VStack(spacing: 0) {
                HRule()
                ForEach(store.pickableActivities.prefix(4)) { activity in
                    Button {
                        store.startSession(activityId: activity.id)
                    } label: {
                        HStack {
                            Text(activity.name).textStyle(.stepName)
                            Spacer()
                            Text("↗").font(.custom("DMSans-Bold", fixedSize: 18)).foregroundStyle(Color.orange)
                        }
                        .frame(minHeight: Space.tapTarget)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    HRule()
                }
            }
            .padding(.top, Space.sm)
        }
    }

    /// What the daily fact rests on. The day itself is in here so an app left
    /// open overnight hands out tomorrow's fact tomorrow rather than at the next
    /// cold launch; the two health counts catch a sync that changed what the
    /// history holds.
    private var dailyFactInputs: [Int] {
        // Reflections as well as sessions: the coverage generator reads only
        // rated sessions, so somebody rating a session they logged this morning
        // changes the answer without changing any of the other counts.
        [Int(today.timeIntervalSinceReferenceDate),
         store.sessions.count, store.reflections.count,
         store.healthByDay.count,
         store.healthByDay.values.reduce(0) { $0 + $1.count }]
    }

    /// What the slot rests on, reduced to something cheap to compare. The engine
    /// is deterministic over the record, so nothing else can move its answer.
    private var recommendationInputs: [Int] {
        [store.sessions.count, store.reflections.count, store.profile.priorities.count,
         store.healthByDay.count, store.physiologyReadings.count,
         // Accepting, refusing, stopping or acknowledging all have to re-run this,
         // or the band would keep offering a proposal somebody has just taken on.
         // Declines are counted too: refusing one is what promotes the next.
         store.experiments.count, store.declinedExperiments.count,
         store.experiments.filter { $0.phase == .active }.count,
         store.experiments.filter { $0.phase == .settled }.count]
    }
}

/// T2 — a running session. Elapsed time, the activity's own mark, and a discreet
/// stop. There is no pause in V1.
private struct ActiveSessionPanel: View {
    @Environment(HourssStore.self) private var store
    let session: Session

    private var glyph: ActivityGlyph.Kind {
        .forActivity(named: store.activityName(session.activityId))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .center, spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Eyebrow("Now", color: .subtleOnDark)
                    Text(store.activityName(session.activityId)).textStyle(.stepName)

                    if let intention = session.intention, !intention.isEmpty {
                        Text(intention).textStyle(.body).foregroundStyle(Color.mutedOnDark)
                    }

                    TimelineView(.periodic(from: session.startAt, by: 1)) { context in
                        Text(elapsed(at: context.date))
                            .font(.custom("DMMono-Medium", fixedSize: 34))
                            .monospacedDigit()
                            .foregroundStyle(Color.lime)
                            .accessibilityLabel("Running for \(elapsedSpoken(at: context.date))")
                    }
                    .padding(.top, Space.xs)
                }

                Spacer(minLength: Space.sm)

                // The only thing on this screen that moves other than the clock,
                // and it is deliberately the slower of the two: the number is the
                // information, the mark is company for it.
                AnimatedActivityGlyph(kind: glyph, size: 64, color: .lime)
                    .accessibilityHidden(true)
            }

            HRule(color: .forestRule)

            if let reason = store.live?.unavailableReason {
                Text(reason)
                    .textStyle(.label)
                    .foregroundStyle(Color.mutedOnDark)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("live-activity-unavailable")
            }

            PrimaryAction(title: "Stop and reflect") {
                store.stopSession(session.id)
            }
            .accessibilityIdentifier("stop-session")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .blockSurface(Color.forest)
        .surfaceContent(.forest)
    }

    private func elapsedSeconds(at date: Date) -> Int {
        max(0, Int(date.timeIntervalSince(session.startAt)))
    }

    private func elapsed(at date: Date) -> String {
        let total = elapsedSeconds(at: date)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func elapsedSpoken(at date: Date) -> String {
        let minutes = elapsedSeconds(at: date) / 60
        return minutes < 1 ? "less than a minute" : "\(minutes) minutes"
    }
}

func formatMinutes(_ minutes: Int) -> String {
    guard minutes > 0 else { return "under a minute" }
    let hours = minutes / 60
    let mins = minutes % 60
    if hours == 0 { return "\(mins)m" }
    return mins == 0 ? "\(hours)h" : "\(hours)h \(mins)m"
}

/// Compact form for the places where the long phrasing would not fit.
func formatMinutesShort(_ minutes: Int) -> String {
    minutes > 0 ? formatMinutes(minutes) : "<1m"
}

/// The line under a day's date. Leads with the total, unless there isn't one yet.
func daySummary(minutes: Int, sessionCount: Int) -> String {
    let noun = sessionCount == 1 ? "session" : "sessions"
    guard minutes > 0 else { return "\(sessionCount) \(noun) logged" }
    return "\(formatMinutes(minutes)) logged across \(sessionCount) \(noun)"
}
