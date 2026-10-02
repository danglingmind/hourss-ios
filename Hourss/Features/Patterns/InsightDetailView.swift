import SwiftUI

/// P3 — the claim, the numbers behind it, the sessions it was computed from, a
/// caveat, and one small experiment.
///
/// The evidence strip and session list are read from the same store the claim was
/// derived from, so they cannot disagree with it.
struct InsightDetailView: View {
    @Environment(HourssStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let insight: Insight

    private var current: Insight { store.insights.first { $0.id == insight.id } ?? insight }

    /// The proposal for this claim, if the design layer can build one.
    ///
    /// Held in state and filled by a task rather than computed in `body`, because
    /// building proposals runs the engine and the correction. This screen is pushed,
    /// so that happens once per visit instead of once per redraw.
    @State private var proposal: ExperimentDesign.Proposal?

    /// This claim's own experiment, where one has been agreed to.
    ///
    /// Matched by hashing each stored key rather than by storing the insight id
    /// alongside it: `Engine.identity` is one-way, so the only way back is forwards,
    /// and it is a hash over a handful of strings rather than an engine run.
    private var mine: Experiment? {
        store.experiments.first { Engine.identity(of: $0.hypothesisId) == current.id }
    }

    /// What this claim offers, which is the one place the old `experiment` string
    /// used to sit.
    ///
    /// **This replaces a sentence that did nothing.** `Hypothesis.experiment` was
    /// rendered here as "Try this: try moving one morning block to a different hour
    /// this week and see whether it still reads the same" — and nothing recorded that
    /// anybody had, nothing measured a window, and nothing reported back. It was the
    /// word without the mechanism, on two of six families, and it is why patterns
    /// left nobody anything to do.
    ///
    /// Four states, and the order matters: what happened, then what is happening,
    /// then what is on offer, then nothing. A claim with nothing to offer shows
    /// nothing rather than an empty heading — `ExperimentDesign` documents which
    /// shapes cannot honestly be tested, and a reader of one of those should not be
    /// told a test is missing.
    @ViewBuilder
    private var experimentBlock: some View {
        if let mine, let settlement = mine.settlement {
            block(eyebrow: ExperimentCopy.verdictTitle(settlement.verdict),
                  text: ExperimentCopy.result(for: mine, settlement: settlement))
        } else if let mine, mine.phase == .active {
            block(eyebrow: "You are testing this", text: mine.change)
        } else if let proposal {
            VStack(alignment: .leading, spacing: Space.xs) {
                HRule()
                Eyebrow(ExperimentCopy.eyebrow(for: proposal.standing))
                Text(proposal.change)
                    .textStyle(.body)
                    .fixedSize(horizontal: false, vertical: true)
                DirectionalLink(title: ExperimentCopy.startTitle, arrow: "→") {
                    _ = store.acceptExperiment(proposal)
                }
                .accessibilityIdentifier("accept-experiment")

                // The same second offer Today carries, for the same reason and with
                // the same ask attached. A claim somebody opened the detail screen
                // to read is if anything the likelier place to take the harder test.
                if let ask = proposal.randomisedAsk {
                    DirectionalLink(title: ExperimentCopy.randomiseTitle, arrow: "→") {
                        _ = store.acceptRandomisedExperiment(proposal)
                    }
                    .accessibilityIdentifier("randomise-experiment")

                    Text(ask)
                        .textStyle(.label)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func block(eyebrow: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HRule()
            Eyebrow(eyebrow)
            Text(text)
                .textStyle(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(eyebrow). \(text)")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Eyebrow(current.band.label)
                    Text(current.statement)
                        .textStyle(.sectionLead)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("An observation, not a rule.")
                        .textStyle(.label)
                        .foregroundStyle(Color.orange)
                }
                .padding(.top, Space.md)

                comparison
                sessionList

                VStack(alignment: .leading, spacing: Space.xs) {
                    HRule()
                    Eyebrow("Bear in mind")
                    Text(current.caveat)
                        .textStyle(.body)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                experimentBlock

                actions
            }
            .pageGutter()
            .padding(.bottom, Space.xl)
        }
        .task {
            // Only when there is nothing to show already: a claim this person has
            // tested does not need a proposal built for it, and that is the case
            // where the engine run would be purely wasted.
            guard mine == nil else { return }
            proposal = store.experimentProposals().first { $0.id == current.id }
        }
        .background(Color.canvas)
        .navigationBarBackButtonHidden()
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Text("←").font(.custom("DMSans-Bold", fixedSize: 18)).foregroundStyle(Color.orange)
                            Text("Patterns").textStyle(.action)
                        }
                        .frame(minHeight: Space.tapTarget)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("back")
                    Spacer()
                }
                .pageGutter()
                HRule()
            }
            .background(Color.canvas)
        }
    }

    /// The evidence: two bars on the 1–5 feeling scale.
    ///
    /// This used to sit under a sentence spelling out the same four numbers.
    /// The sentence is gone; `ComparisonMark` carries them, and its chart
    /// descriptor keeps them in the VoiceOver path.
    private var comparison: some View {
        let e = current.evidence
        return VStack(alignment: .leading, spacing: Space.sm) {
            HRule()
            Eyebrow("Average feeling · \(e.windowDescription)")
            ComparisonMark(rows: [
                .init(label: e.comparisonLabel, value: e.comparisonValue, count: e.comparisonCount, highlighted: true),
                .init(label: e.baselineLabel, value: e.baselineValue, count: e.baselineCount, highlighted: false),
            ])
            Text("1 draining → 5 energizing. Unrated sessions left out.")
                .textStyle(.label)
                .foregroundStyle(Color.muted)
        }
    }

    private var sessionList: some View {
        let sessions = store.sessions(for: current).prefix(12)
        return VStack(alignment: .leading, spacing: 0) {
            HRule()
            Eyebrow("Behind this")
                .padding(.bottom, Space.xs)
            ForEach(Array(sessions), id: \.id) { session in
                HStack {
                    Text(session.startAt.formatted(.dateTime.day().month(.abbreviated)))
                        .textStyle(.label)
                        .foregroundStyle(Color.muted)
                        .frame(width: 56, alignment: .leading)
                    Text(store.activityName(session.activityId)).textStyle(.body)
                    Spacer()
                    if let feeling = store.feeling(for: session.id) {
                        Text("\(feeling)/5").textStyle(.label)
                    } else {
                        Text("—").textStyle(.label).foregroundStyle(Color.muted)
                    }
                }
                .padding(.vertical, Space.xs)
                .frame(minHeight: 36)
                HRule()
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            HRule()
            HStack(spacing: Space.lg) {
                Button(current.status == .saved ? "Saved" : "Save this") {
                    store.setStatus(current.status == .saved ? .visible : .saved, for: current.id)
                }
                .buttonStyle(.plain)
                .textStyle(.action)
                .foregroundStyle(current.status == .saved ? Color.orange : Color.ink)
                .frame(minHeight: Space.tapTarget)

                Button("Not me") {
                    store.setStatus(.hidden, for: current.id)
                    dismiss()
                }
                .buttonStyle(.plain)
                .textStyle(.action)
                .foregroundStyle(Color.muted)
                .frame(minHeight: Space.tapTarget)
                .multilineTextAlignment(.leading)
            }
        }
    }
}
