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

                evidence
                comparison
                sessionList

                VStack(alignment: .leading, spacing: Space.xs) {
                    HRule()
                    Eyebrow("Worth keeping in mind")
                    Text(current.caveat)
                        .textStyle(.body)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let experiment = current.experiment {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HRule()
                        Eyebrow("If you want to test it")
                        Text(experiment)
                            .textStyle(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                actions
            }
            .pageGutter()
            .padding(.bottom, Space.xl)
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

    private var evidence: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HRule()
            Eyebrow("The evidence")
            Text(current.evidence.summary)
                .textStyle(.body)
                .foregroundStyle(Color.muted)
        }
    }

    /// The small chart: two bars on the 1–5 feeling scale, labelled with their
    /// values so the comparison never depends on reading bar lengths.
    private var comparison: some View {
        let e = current.evidence
        return VStack(alignment: .leading, spacing: Space.sm) {
            HRule()
            Eyebrow("Average feeling")
            bar(label: e.comparisonLabel, value: e.comparisonValue, count: e.comparisonCount, highlighted: true)
            bar(label: e.baselineLabel, value: e.baselineValue, count: e.baselineCount, highlighted: false)
            Text("Rated 1 (draining) to 5 (energizing). Unrated sessions are left out.")
                .textStyle(.label)
                .foregroundStyle(Color.muted)
        }
    }

    private func bar(label: String, value: Double, count: Int, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).textStyle(.body)
                Spacer()
                Text(String(format: "%.1f", value)).textStyle(.label)
                Text("· \(count) sessions").textStyle(.label).foregroundStyle(Color.muted)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.ink.opacity(0.08))
                    Rectangle()
                        .fill(highlighted ? Color.lime : Color.rule)
                        .frame(width: geo.size.width * min(1, value / 5))
                }
            }
            .frame(height: 22)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): average \(String(format: "%.1f", value)) out of 5, from \(count) sessions")
    }

    private var sessionList: some View {
        let sessions = store.sessions(for: current).prefix(12)
        return VStack(alignment: .leading, spacing: 0) {
            HRule()
            Eyebrow("The sessions behind this")
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

                Button("That doesn't sound like me") {
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
