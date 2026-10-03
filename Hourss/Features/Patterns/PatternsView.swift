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

/// Where Patterns can push to.
///
/// One case, and an enum rather than a bare `TestsView()` destination, because a
/// value route is what lets the entry be a `NavigationLink` instead of a sheet or a
/// tab: `Insight` already takes the other route off this screen, and a second
/// `navigationDestination` keyed on a type nobody else uses keeps the two from ever
/// resolving to each other.
enum PatternsRoute: Hashable {
    case tests
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

    /// Questions the engine cannot ask yet, with what each is short of.
    ///
    /// Cached beside the leads, though for the opposite reason: this one runs no
    /// bootstrap at all — nothing in it has been compared — so it is cheap. It is
    /// held here only so it refreshes on the same key as everything else and cannot
    /// disagree with the findings drawn beside it.
    @State private var waiting: [Engine.Pending] = []

    /// The proposal whose sheet is up, if one is. Agreeing happens on a screen of
    /// its own, here exactly as on Today — the same sheet, so the four answers
    /// somebody reads before saying yes do not depend on which tab they were on.
    @State private var sheetProposal: ExperimentDesign.Proposal?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                if store.isWarmingUp {
                    warmingUp
                } else {
                    ranked
                }

                // Outside both branches, which is the whole reason it is here and
                // not inside `ranked`. A warming-up record has no groups and no
                // claims, but `ExperimentDesign` still offers a starter — the one
                // thing the app can propose early — so a tests entry that lived in
                // the ranked branch would be missing on exactly the weeks when the
                // only thing somebody can do about their record is agree to a test.
                // Today's observation slot sits outside its two branches for the
                // same reason and the comment there names the bug it caught.
                testsEntry
            }
            .pageGutter()
            .padding(.bottom, Space.xl)
        }
        .task(id: leadInputs) {
            leads = Self.leads(in: store)
            proposals = store.experimentProposals()
            waiting = Engine.pending(for: EngineInput(observations: store.engineObservations,
                                                      priorities: store.profile.priorities))
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Patterns")
        }
        .navigationDestination(for: Insight.self) { InsightDetailView(insight: $0) }
        .navigationDestination(for: PatternsRoute.self) { _ in TestsView() }
        .sheet(item: $sheetProposal) { proposal in
            TestProposalSheet(proposal: proposal)
        }
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

                // The gate itself, named. Every other row here counts one thing;
                // this one counts the thing that actually decides whether a
                // comparison exists — six distinct days on each side, not twelve in
                // total. Somebody logging only mornings can fill every other bar on
                // this screen and still have nothing to compare, and before this the
                // screen left them to work that out themselves.
                coverageRow(
                    "Days on both sides",
                    detail: "\(min(store.bestBalancedDays, EvidenceFloor.perSide)) of \(EvidenceFloor.perSide)"
                ) {
                    DataBar(fraction: min(Double(store.bestBalancedDays) / Double(EvidenceFloor.perSide), 1),
                            height: DataBar.strip)
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


            Text("Observations, not rules. Hourss only speaks up when the same thing repeats.")
                .textStyle(.label)
                .foregroundStyle(Color.muted)
        }
    }

    /// The way into the tests feature.
    ///
    /// **Why it is here and not on You.** A test has two halves and they do not
    /// belong in the same place. The record half — a fortnight somebody agreed to
    /// and lived through — is a statement of what this person has done, which is
    /// what You is for, and that is the argument `ExperimentHistory` was written
    /// with. The offer half is not: "try mornings for a fortnight" is a thing to do
    /// about a claim, and claims live here. A settings list is the wrong shelf for
    /// something nobody has done yet, and the record was dragging the offer onto it.
    ///
    /// **Why it reads as a continuation and not as a link.** Every priority group
    /// above ends with the one thing to try for that priority, and `prioritySection`
    /// raises the same sheet Today raises. So the relationship already exists on this
    /// screen, several times over, in the one form that cannot be mistaken for
    /// navigation. This entry is the question those rows leave behind — what came of
    /// the ones I said yes to — so it is in the groups' own idiom: an eyebrow, a
    /// rule, a sentence at `.body`, and a directional link. Nothing about it is a
    /// `SettingsRow`.
    ///
    /// **Why the foot of the screen and not the head.** A row above the lead
    /// observation would put navigation in the position this screen reserves for the
    /// strongest thing the app has noticed, and a strip of rows under a header is
    /// precisely the settings shape to avoid — it was the shape it had on You. At the
    /// foot it follows the claims, the conjunctions and the leads, which is the order
    /// of the reading: here is what held up, here is what we are watching, here is
    /// what you tried. The sign-off above it — "Observations, not rules" — closes the
    /// evidence half and now doubles as the boundary between what the app noticed and
    /// what this person did about it.
    ///
    /// **The sentence names the destination's three sections and states nothing
    /// else.** No tally and no newest verdict: a count here would be the one number
    /// this feature refuses to compute, and naming the latest result or that an offer
    /// is waiting would put a verdict in a second place and let the two drift.
    /// `TestsView` carries the longer form of both arguments.
    private var testsEntry: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("Testing")
                .padding(.bottom, Space.xs)
            HRule()
            NavigationLink(value: PatternsRoute.tests) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("What is on offer, what is running, and everything that finished.")
                        .textStyle(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    // "→", the arrow this app uses for a push, as the lead card and
                    // the insight rows above already do. "↘" is the other screen's
                    // mark for opening a longer list in place.
                    HStack(spacing: 6) {
                        Text("Your tests").textStyle(.action)
                        Text("→").font(.custom("DMSans-Bold", fixedSize: 18)).foregroundStyle(Color.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Space.sm)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("row-tests")
            HRule()
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

    /// One question, said in two steps: what it is about, then where it stands.
    ///
    /// The same shape whether it was measured and came out alike or has not been
    /// measured at all, because the difference between those is what the second line
    /// says and not how loudly it is drawn. A waiting question dimmed or badged
    /// would read as unavailable, which is the mistake the leads section already
    /// made once by printing its rows in grey.
    private func questionRow(title: String, detail: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .textStyle(.body)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .textStyle(.label)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityIdentifier(identifier)
        .overlay(alignment: .bottom) { HRule() }
    }

    /// Questions this priority covers that cannot be asked yet.
    ///
    /// **Not sorted by how close they are.** Ordering by closeness turns the screen
    /// into a list of things to go and log next, which is how a record becomes a
    /// chore — `PRD-LOCKS.md` §6. They come out in the registry's own order, which is
    /// stable between runs and means nothing.
    private func waiting(for priority: Priority?) -> [Engine.Pending] {
        guard let priority else { return [] }
        return waiting.filter { priority.insightTypes.contains($0.hypothesis.type) }
    }

    /// Leads this priority covers — questions that were asked and came out alike.
    ///
    /// They used to have a section of their own at the foot of the screen. That said
    /// a measured non-answer belongs somewhere other than with the answers, which is
    /// the opposite of what this app believes: `QuestionCopy` has the argument.
    private func leads(for priority: Priority?) -> [Finding] {
        guard let priority else { return [] }
        return leads.filter { priority.insightTypes.contains($0.publishedType) }
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

            // Measured, and came out alike. Beside the answers rather than in a
            // section of its own, because a measured non-answer is an answer.
            ForEach(leads(for: priority), id: \.hypothesis.id) { lead in
                questionRow(title: lead.hypothesis.focusLabel,
                            detail: QuestionCopy.noSeparation,
                            identifier: "lead-row")
            }

            if items.isEmpty && leads(for: priority).isEmpty && proposal == nil
                && waiting(for: priority).isEmpty {
                Text("Nothing here has repeated enough to show.")
                    .textStyle(.body)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, Space.sm)
                HRule()
            }

            // The one thing to try for this priority, where somebody is already
            // looking at how it is going. Today shows the same offer; this is the
            // same proposal and now the same sheet, so agreeing here or there is one
            // act, reads the same four answers first, and cannot produce two
            // experiments.
            if let proposal {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(proposal.change)
                        .textStyle(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    DirectionalLink(title: ExperimentCopy.openTitle, arrow: "→") {
                        sheetProposal = proposal
                    }
                    .accessibilityIdentifier("open-proposal")
                }
                .padding(.vertical, Space.sm)
                HRule()
            }

            // What this priority is still waiting on. Last, because it is the only
            // part of the section that has not been measured — everything above it
            // is something the app has actually looked at.
            //
            // Under its own small heading rather than running straight on, so that a
            // reader can tell at a glance where the answers stop. Without it the
            // first waiting row reads as a finding whose sentence happens to be about
            // days.
            let unasked = waiting(for: priority)
            if !unasked.isEmpty {
                Eyebrow(QuestionCopy.waitingHeading)
                    .padding(.top, Space.sm)
                    .padding(.bottom, Space.xs)
                HRule()
                ForEach(unasked, id: \.hypothesis.id) { question in
                    questionRow(title: question.hypothesis.focusLabel,
                                detail: QuestionCopy.waiting(question),
                                identifier: "waiting-row")
                }
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
