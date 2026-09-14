import SwiftUI

/// Conjunctions, in the feed.
///
/// A section of their own rather than rows among the single-factor observations,
/// because they are a different kind of claim: a conjunction says two conditions
/// together do something neither does alone, and reading that in a list of "your
/// mornings have felt better" invites somebody to take it as a stronger version
/// of the same thing. It is not stronger. It is narrower, and it survived a
/// different correction to get here.
///
/// The section is absent, not empty, when nothing survived. Most people will see
/// nothing here for a long time and some will never see anything, which is the
/// search working rather than failing.
struct InteractionSection: View {
    let findings: [InteractionFinding]
    let observations: [EngineObservation]

    @Environment(NarrationStore.self) private var narration

    var body: some View {
        if !findings.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("Together")
                    .padding(.bottom, Space.xs)
                HRule()

                ForEach(Array(evidence.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(narration.sentence(for: item))
                            .textStyle(.body)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("An association across conditions, not a cause.")
                            .textStyle(.label)
                            .foregroundStyle(Color.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Space.sm)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("interaction-row")

                    HRule()
                }
            }
            .task(id: findings.map(\.conjunction.id).joined()) {
                // Fire and forget. The template is already on screen; if a model
                // exists it replaces the sentence in place, and if it does not
                // this does nothing at all. Nothing waits on it either way.
                for item in evidence { narration.refine(item) }
            }
        }
    }

    private var evidence: [NarrationEvidence] {
        findings.compactMap { NarrationEvidence(finding: $0, observations: observations) }
    }
}
