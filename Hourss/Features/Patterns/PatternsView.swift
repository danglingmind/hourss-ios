import SwiftUI

/// The warm-up readout, split into the thing being counted and the count.
///
/// Two strings rather than one sentence because the order matters and the order
/// is the bug being fixed: the whole line used to be "3 of 12 days with a
/// rating", which names its subject four words after the figure. Naming it first
/// costs nothing — the words are the same words — and holding the halves apart
/// lets a test assert which one leads.
///
/// The title is a restatement of wording already on this screen, not a new claim,
/// so it carries no causal, clinical, population or instruction vocabulary to
/// answer for.
enum EvidenceReadout {
    /// What is being counted.
    static let title = "Days with a rating"

    /// How many, against the floor the engine actually requires.
    static func figure(days: Int, floor: Int = EvidenceFloor.days) -> String {
        "\(days) of \(floor)"
    }
}

/// P1 and P2. The warm-up state is not a placeholder chart — the spec forbids
/// fake charts and premature observations, so before there is evidence the screen
/// says so plainly.
struct PatternsView: View {
    @Environment(HourssStore.self) private var store

    /// What the engine is watching but cannot yet claim.
    ///
    /// Held in state and filled by a task rather than computed in `body`, because
    /// producing it runs the engine and the correction — the same reason
    /// `TodayView` caches its recommendations. A view body re-evaluates far more
    /// often than the engine should.
    @State private var leads: [Finding] = []

    /// One proposal per priority, cached for the same reason the leads are: building
    /// them runs the engine and the correction, and a view body re-evaluates far
    /// more often than the engine should.
    @State private var proposals: [ExperimentDesign.Proposal] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                if store.isWarmingUp {
                    warmingUp
                } else {
                    ranked
                }
            }
            .pageGutter()
            .padding(.bottom, Space.xl)
        }
        .task(id: leadInputs) {
            leads = Self.leads(in: store)
            proposals = store.experimentProposals()
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Patterns")
        }
        .navigationDestination(for: Insight.self) { InsightDetailView(insight: $0) }
    }

    /// P1 — warming up.
    ///
    /// This used to be a paragraph restating the progress bar beneath it, then
    /// three lines of generic advice. The marks are computed from real sessions,
    /// so they say what is actually thin rather than what usually is.
    private var warmingUp: some View {
        // Days, not sessions. The engine requires six distinct days on each side
        // of any comparison and never counts sessions at all, so a session total
        // told somebody they were two thirds of the way to something that was not
        // being measured. Six sessions on one Tuesday are one day of evidence
        // about Tuesdays.
        //
        // Held in a value rather than written inline so the spoken form can be
        // taken from the same object the screen draws, and so the two halves
        // cannot drift into the wrong order.
        let evidence = TitledFigure(
            title: EvidenceReadout.title,
            figure: EvidenceReadout.figure(days: store.ratedDayCount)
        )

        return VStack(alignment: .leading, spacing: Space.md) {
            DisplayHeadline([
                Text("Still").styled(.sectionTitle),
                Text("listening.").styled(.emphasis(42)),
            ], style: .sectionTitle)
            .padding(.top, Space.md)

            HRule()

            // The figure named what it counted, but only after saying how many —
            // and at 26pt with nothing above it, the number was the whole glance.
            // Subject on the top step, count on the second.
            VStack(alignment: .leading, spacing: Space.xs) {
                evidence
                // The bar repeats the figure above it and speaks nothing of its
                // own; combining the block keeps the count from being read twice.
                DataBar(fraction: store.evidenceProgress, height: DataBar.progress)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(evidence.spoken)

            HRule()

            VStack(alignment: .leading, spacing: Space.md) {
                coverageRow(
                    "Times of day",
                    detail: "\(store.timeBucketsCovered.filter { $0 }.count) of 4"
                ) {
                    CoverageMark(segments: store.timeBucketsCovered, height: DataBar.strip)
                }

                coverageRow(
                    "Sessions rated",
                    detail: "\(Int(store.ratedShare * 100))%"
                ) {
                    DataBar(fraction: store.ratedShare, height: DataBar.strip)
                }

                coverageRow(
                    "Weeks logged",
                    detail: String(format: "%.0f of 6", store.weeksOfHistory.rounded())
                ) {
                    DataBar(fraction: store.weeksOfHistory / 6, height: DataBar.strip)
                }
            }
        }
    }

    private func coverageRow<Mark: View>(
        _ title: String,
        detail: String,
        @ViewBuilder mark: () -> Mark
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(title).textStyle(.body)
                Spacer()
                Text(detail).textStyle(.label).foregroundStyle(Color.muted)
            }
            mark()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(detail)")
    }

    /// P2 — one lead observation, then a sparse grouped feed.
    private var ranked: some View {
        let insights = store.visibleInsights

        return VStack(alignment: .leading, spacing: Space.lg) {
            if let lead = insights.first {
                NavigationLink(value: lead) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Eyebrow("Here's something we're noticing", color: .subtleOnDark)
                        Text(lead.statement)
                            .textStyle(.sectionLead)
                        Text(lead.evidence.summary)
                            .textStyle(.label)
                            .foregroundStyle(Color.mutedOnDark)
                        HStack(spacing: 6) {
                            Text("See the evidence").textStyle(.action)
                            Text("→").font(.custom("DMSans-Bold", fixedSize: 18)).foregroundStyle(Color.orange)
                        }
                        .padding(.top, Space.xs)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.md)
                    .blockSurface(Color.forest)
                    .surfaceContent(.forest)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lead-insight")
                .padding(.top, Space.md)
            }

            ForEach(byPriority(insights.dropFirst().map { $0 }), id: \.0) { priority, items in
                prioritySection(priority, items)
            }

            // Outside the loop. It used to sit inside it, so a person with three
            // groups saw the same conjunctions three times.
            InteractionSection(findings: store.interactions,
                               observations: store.engineObservations)

            leadSection

            Text("Observations, not rules. Hourss only speaks up when the same thing repeats.")
                .textStyle(.label)
                .foregroundStyle(Color.muted)
        }
    }

    /// Rung 2 — what is being watched, said plainly as being watched.
    ///
    /// **Why this is a section and not a claim.** Everything above it cleared the
    /// interval gate and the correction. Nothing here has. Until now a lead was
    /// visible only in the moment it became the proposal on Today, which meant the
    /// app was quietly tracking several things about somebody and showing them one,
    /// with no way to see the rest — and no way to tell that the one they *were*
    /// shown came from a pool rather than being the only thing there was.
    ///
    /// The day count is on every row and is doing the work the eyebrow cannot: it
    /// is the difference between "your mornings are better" and "four days so far
    /// have read that way". `ExperimentCopy.premise` writes the sentence, rather
    /// than this file writing a second phrasing of the same thing.
    ///
    /// No navigation. A lead has no detail screen because there is no evidence page
    /// to show — an interval that spans zero and a correction it did not survive is
    /// not a case somebody should be invited to read as though it were one.
    @ViewBuilder
    private var leadSection: some View {
        if !leads.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Everything in this section is a lead by construction, so the
                // standing is named once here rather than per row — but through the
                // same function the cards use, so a rename cannot leave the list
                // and the card calling the same thing two names.
                Eyebrow(ExperimentCopy.eyebrow(for: .lead))
                    .padding(.bottom, Space.xs)
                HRule()
                ForEach(leads, id: \.hypothesis.id) { lead in
                    // Ink, not muted.
                    //
                    // These were grey, and grey is the wrong signal: on every other
                    // screen it means a thing is off, spent or unavailable, so a
                    // column of grey rows under a live heading read as disabled.
                    // They are not. They are ordinary observations that have not
                    // repeated enough to be claimed.
                    //
                    // Two things already say that — the heading above them and the
                    // day count inside every row — so the colour was a third signal
                    // doing a job two were already doing, and doing it wrongly.
                    Text(ExperimentCopy.premise(for: lead, standing: .lead,
                                                days: lead.comparison.focusDays))
                        .textStyle(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Space.sm)
                    HRule()
                }

                // Says outright that these are not findings. No "yet" and no
                // "soon": for somebody whose days genuinely are flat none of these
                // will ever firm up, and a word that promises otherwise is a
                // promise the engine cannot keep.
                Text("These have not repeated enough to stand on their own. They are what Hourss is watching.")
                    .textStyle(.label)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.sm)
            }
            // `children: .contain` so the identifier actually resolves to a
            // container. Without it the rows stay independent elements, the
            // identifier lands on nothing a query can find, and a UI test looking
            // for this section reports it absent while it is plainly on screen.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("lead-section")
        }
    }

    /// Cheap to compare, and moves whenever the engine's answer could.
    private var leadInputs: [Int] {
        [store.sessions.count, store.reflections.count,
         store.healthByDay.count, store.physiologyReadings.count,
         store.experiments.count, store.declinedExperiments.count]
    }

    /// Directional findings that did not clear the gates, most surprising first.
    ///
    /// Filtered through `ExperimentDesign` rather than by hand so that this list and
    /// the proposal on Today can never disagree about what counts as a lead: a row
    /// here that could not become a test would be the app naming something it has no
    /// intention of doing anything about.
    ///
    /// Anything already declined or already tested is dropped, for the same reason
    /// it is dropped from proposals — re-surfacing a question somebody has answered
    /// is the app not listening.
    /// Exposed rather than private so a test can assert what reaches the screen
    /// without rendering anything. It stays `@MainActor` by inference from the view,
    /// which is correct — it reads a `@MainActor` store — so the suite that calls it
    /// is marked `@MainActor` too. Making it `nonisolated` instead would compile and
    /// then trap at runtime, which in this project has twice looked like a shrinking
    /// test count rather than a crash.
    static func leads(in store: HourssStore) -> [Finding] {
        let input = EngineInput(observations: store.engineObservations,
                                priorities: store.profile.priorities)
        let excluded = store.experimentKeysToExclude
        let findings = Engine.applyingCorrection(to: Engine.findings(for: input))
        return Surprise.ranked(
            findings.filter {
                ExperimentDesign.isEligible($0)
                    && ExperimentDesign.standing(of: $0) == .lead
                    && !excluded.contains($0.hypothesis.id)
            }
        )
    }

    /// One section per thing somebody said mattered, in the order they ranked them.
    ///
    /// **This used to group by `type.group`** — "Timing", "Activities", "Energy",
    /// "Body". Those are the engine's words for its own families. Nobody chose them
    /// and nobody was asked about them. Onboarding asks what matters and offers
    /// Focus, Energy, Sleep, Movement, Calm and Balance, and until now the answer
    /// only changed what order things came in. A person who said focus mattered had
    /// no screen that answered how focus was going.
    ///
    /// An insight can serve more than one priority, so it is filed under the
    /// highest-ranked one that claims it and appears once. Anything no stated
    /// priority claims is kept in a final group rather than dropped — it is still
    /// something true about them.
    private func byPriority(_ insights: [Insight]) -> [(Priority?, [Insight])] {
        var remaining = insights
        var out: [(Priority?, [Insight])] = []

        for priority in store.profile.priorities {
            let mine = remaining.filter { priority.insightTypes.contains($0.type) }
            remaining.removeAll { priority.insightTypes.contains($0.type) }
            // Kept even when empty: a priority with nothing to show still gets a
            // section saying so, because silence reads as the app having nothing
            // rather than as nothing having repeated.
            out.append((priority, mine))
        }
        if !remaining.isEmpty { out.append((nil, remaining)) }
        return out
    }

    /// What one priority has to say: what held up, and the one thing to try.
    @ViewBuilder
    private func prioritySection(_ priority: Priority?, _ items: [Insight]) -> some View {
        let proposal = priority.flatMap { p in proposals.first { $0.priority == p } }

        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(priority?.title ?? "Everything else")
                .padding(.bottom, Space.xs)
            HRule()

            ForEach(items) { insight in
                NavigationLink(value: insight) {
                    InsightRow(insight: insight)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("insight-row")
                HRule()
            }

            if items.isEmpty && proposal == nil {
                Text("Nothing here has repeated enough to show.")
                    .textStyle(.body)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, Space.sm)
                HRule()
            }

            // The one thing to try for this priority, where somebody is already
            // looking at how it is going. Today shows the same offer; this is the
            // same proposal and the same control, so accepting here or there is one
            // act and cannot produce two experiments.
            if let proposal {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(proposal.change)
                        .textStyle(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    DirectionalLink(title: ExperimentCopy.startTitle, arrow: "→") {
                        _ = store.acceptExperiment(proposal)
                    }
                    .accessibilityIdentifier("accept-experiment")
                }
                .padding(.vertical, Space.sm)
                HRule()
            }
        }
    }
}

private struct InsightRow: View {
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(insight.statement)
                .textStyle(.body)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(insight.band.label)
                    .textStyle(.label)
                    .foregroundStyle(Color.orange)
                Spacer()
                Text(insight.status == .saved ? "Saved" : "")
                    .textStyle(.label)
                    .foregroundStyle(Color.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.sm)
        .contentShape(.rect)
    }
}

/// Shared top bar for the tabbed screens.
struct ScreenHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Wordmark()
                Spacer()
                Eyebrow(trailing ?? title)
            }
            .pageGutter()
            .padding(.vertical, Space.gutter)
            HRule()
        }
        .background(Color.canvas)
    }
}
