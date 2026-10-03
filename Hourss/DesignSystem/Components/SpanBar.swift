import SwiftUI

/// A stretch of time, drawn as the stretch rather than described as one.
///
/// **What it replaced.** `TestProposalSheet`'s "How long" section was the sentence
/// "Two weeks, from the day you start." — which is accurate and leaves the one fact
/// a reader actually wants to the reader: when this finishes. The owner asked for
/// the length shown as a figure with a bar under it running from today to the end
/// date, and that is this.
///
/// **Why the bar is solid and not part-filled.** It is not progress. Nothing has
/// elapsed when this is read, and a part-filled bar would be claiming otherwise,
/// while an empty track is the app's own mark for *unknown* — `DataBar` renders a
/// nil fraction as bare track precisely so an unrated session never looks like a
/// zero. What this draws is an extent: the whole of a commitment, with its two ends
/// named. So the bar is whole, and it is `ruleColor` rather than `lime` because lime
/// is the colour of a value somebody's record produced and no value exists yet.
///
/// **Why not fourteen day cells.** `CoverageMark` draws equal segments, some filled,
/// and fourteen unfilled ones would have counted the days and previewed the mark the
/// active-test card fills in as the window runs — which was tempting. It was dropped
/// because that card's mark means *days with a rating*, a different and much harder
/// quantity than calendar length, and two marks of one shape meaning two things on
/// consecutive screens is how a reader learns the wrong thing.
///
/// Hidden from VoiceOver: the labels at its ends are spoken by the block that owns
/// it, through `ExperimentCopy.ProposalSheet.Section.spoken`, so a third spoken copy
/// would be the same two dates again.
struct SpanBar: View {
    /// The near end. A word or a date — this never formats either.
    let start: String
    /// The far end.
    let end: String

    @Environment(\.surface) private var surface

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            // Through `DataBar` rather than a `Rectangle` of its own, because four
            // hand-rolled bars at three heights is the mess that component was made
            // to end. A full fraction is a whole bar.
            DataBar(fraction: 1, fill: surface.ruleColor, height: DataBar.progress)
                // The house wipe, and for once it is literal: a window runs
                // left to right, and this is the direction it will run in.
                .revealsOnAppear()

            HStack(alignment: .top, spacing: Space.xs) {
                Text(start)
                    .textStyle(.label)
                    .fixedSize(horizontal: false, vertical: true)
                // Pushed apart rather than laid out in thirds, so at
                // `AccessibilityL` — where an 11pt mono label is some thirty
                // points tall — the two ends wrap instead of overlapping.
                Spacer(minLength: Space.xs)
                Text(end)
                    .textStyle(.label)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(surface.secondary)
        }
        .accessibilityHidden(true)
    }
}

/// A short sequence of gates, each either cleared or not yet.
///
/// **What it replaced.** `TestProposalSheet`'s "How it decided" was one forty-word
/// sentence per standing, three of them, all opening with the same clause. The
/// honest content underneath was a procedure — compared against your own record,
/// then checked against every other pattern in it — and a procedure with two steps
/// and a state each is a thing to draw rather than a thing to write.
///
/// **Fill, not colour.** A cleared gate is a solid square and an uncleared one is a
/// 1pt outline, which is a shape distinction and survives greyscale; the label's own
/// colour moves with it as reinforcement, never as the carrier. The state in words
/// reaches VoiceOver through the copy, not from here — see
/// `ExperimentCopy.ProposalSheet.Stage`.
///
/// **It has to read correctly with nothing cleared**, which is the case that decided
/// the shape: a day-one starter has compared nothing at all, so this draws two empty
/// outlines and no fill anywhere, and the sentence beneath says as much. A mark that
/// could only describe a reading which had got somewhere would have had to be absent
/// for the one standing most in need of an honest answer.
struct StageList: View {
    struct Stage {
        let label: String
        let cleared: Bool
    }

    let stages: [Stage]

    @Environment(\.surface) private var surface

    /// The square, and the drop that seats it on the first line of its label.
    ///
    /// Scaled rather than fixed, which is the geometric half of what `relativeTo:`
    /// does for the type: at `AccessibilityL` a body line is some forty points tall
    /// and an 11pt box beside it reads as a speck somebody forgot to grow.
    @ScaledMetric(relativeTo: .body) private var box: CGFloat = 11
    @ScaledMetric(relativeTo: .body) private var seat: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            // Keyed on the label rather than on a generated id, so a redraw does not
            // hand every row a new identity — the mistake that makes a `ForEach`
            // rebuild its children and refire anything they do on appear.
            ForEach(stages, id: \.label) { stage in
                HStack(alignment: .top, spacing: Space.xs) {
                    mark(cleared: stage.cleared)
                        .padding(.top, seat)
                    Text(stage.label)
                        .textStyle(.body)
                        .foregroundStyle(stage.cleared ? surface.foreground : surface.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Square, like every other mark in this app that is not a curve.
    private func mark(cleared: Bool) -> some View {
        Rectangle()
            .fill(cleared ? surface.foreground : Color.clear)
            .frame(width: box, height: box)
            .overlay {
                Rectangle()
                    .strokeBorder(cleared ? Color.clear : surface.ruleColor, lineWidth: 1)
            }
    }
}
