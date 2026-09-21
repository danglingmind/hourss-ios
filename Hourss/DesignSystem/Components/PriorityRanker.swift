import SwiftUI

/// What you want to improve, in your own order.
///
/// Ranked by tapping in sequence rather than by dragging: reordering needs a
/// `List`, which brings the rounded, inset chrome this system exists without, and
/// a drag handle is a poor target on a first run. Tapping in order says the same
/// thing and can be undone by tapping again.
///
/// Shared between onboarding and Profile rather than written twice, because the
/// order is not decoration — it weights which observations surface first — and two
/// implementations of a control that changes the product is two chances for the
/// second one to rank differently from the first.
struct PriorityRanker: View {
    @Binding var ranked: [Priority]
    var maximum: Int = 3

    var body: some View {
        VStack(spacing: 0) {
            HRule()
            ForEach(Priority.allCases) { priority in
                row(priority)
            }
        }
    }

    private func row(_ priority: Priority) -> some View {
        let rank = ranked.firstIndex(of: priority)

        return Button {
            toggle(priority)
        } label: {
            HStack(alignment: .top, spacing: Space.sm) {
                // The rank number is the whole interaction, so it carries the
                // accent and holds its column whether filled or not.
                Text(rank.map { "\($0 + 1)" } ?? "—")
                    .textStyle(.stepName)
                    .foregroundStyle(rank == nil ? Color.rule : Color.orange)
                    .frame(width: 28, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(priority.title).textStyle(.stepName)
                    Text(priority.basis)
                        .textStyle(.label)
                        .foregroundStyle(Color.muted)
                }
                Spacer(minLength: Space.sm)
            }
            .padding(.vertical, Space.sm)
            .frame(minHeight: Space.tapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("priority-\(priority.rawValue)")
        .accessibilityLabel(rank.map { "\(priority.title), ranked \($0 + 1). \(priority.basis)" }
                            ?? "\(priority.title), not ranked. \(priority.basis)")
        .accessibilityAddTraits(rank != nil ? [.isSelected] : [])
        .overlay(alignment: .bottom) { HRule() }
    }

    /// Tapping a ranked item removes it and closes the gap, so the numbers stay
    /// 1, 2, 3 rather than leaving a hole.
    private func toggle(_ priority: Priority) {
        if let index = ranked.firstIndex(of: priority) {
            ranked.remove(at: index)
        } else if ranked.count < maximum {
            ranked.append(priority)
        }
    }
}
