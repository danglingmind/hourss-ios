import SwiftUI

/// A small mark for each activity, drawn from the system's own vocabulary.
///
/// The design system rules out borrowed iconography, and a bare letter reads as a
/// placeholder. So these are built from the only shapes Hourss has — rectangles,
/// rules and the brand's separated dot — on a shared 12×12 grid at one weight, so
/// the eight of them read as a set rather than eight unrelated pictures.
///
/// They exist for the Dynamic Island, where something must be legible at 16pt with
/// no room for a word. Everything drawn here is a rectangle, so nothing about the
/// editorial system is given up to get one.
struct ActivityGlyph: View {
    let kind: Kind
    var size: CGFloat = 16
    var color: Color = .lime

    enum Kind: String, CaseIterable {
        case deepWork, meetings, admin, learning, creative, exercise, social, rest

        /// Maps an activity name to its mark. Unknown activities fall back to the
        /// neutral block rather than inventing a glyph.
        static func forActivity(named name: String) -> Kind {
            switch name {
            case "Deep work": .deepWork
            case "Meetings": .meetings
            case "Admin": .admin
            case "Learning": .learning
            case "Creative": .creative
            case "Exercise": .exercise
            case "Social": .social
            case "Personal / Rest": .rest
            default: .deepWork
            }
        }
    }

    var body: some View {
        Canvas { context, canvasSize in
            let unit = canvasSize.width / 12
            for rect in rects {
                context.fill(
                    Path(CGRect(
                        x: rect.minX * unit,
                        y: rect.minY * unit,
                        width: rect.width * unit,
                        height: rect.height * unit
                    )),
                    with: .color(color)
                )
            }
            if let dot {
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: dot.x * unit, y: dot.y * unit,
                        width: 3 * unit, height: 3 * unit
                    )),
                    with: .color(.orange)
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Coordinates on a 12×12 grid.
    private var rects: [CGRect] {
        switch kind {
        // One sustained block — undivided attention.
        case .deepWork:
            [CGRect(x: 3, y: 0, width: 6, height: 12)]

        // Three voices side by side.
        case .meetings:
            [CGRect(x: 0, y: 2, width: 3, height: 8),
             CGRect(x: 4.5, y: 0, width: 3, height: 12),
             CGRect(x: 9, y: 2, width: 3, height: 8)]

        // A stack of small things.
        case .admin:
            [CGRect(x: 0, y: 1, width: 12, height: 2),
             CGRect(x: 0, y: 5, width: 12, height: 2),
             CGRect(x: 0, y: 9, width: 8, height: 2)]

        // An open page: a block with a rule under it.
        case .learning:
            [CGRect(x: 0, y: 0, width: 12, height: 7),
             CGRect(x: 0, y: 9, width: 12, height: 2)]

        // A block with the brand's separated dot (see `dot`).
        case .creative:
            [CGRect(x: 0, y: 3, width: 8, height: 9)]

        // Rising steps.
        case .exercise:
            [CGRect(x: 0, y: 8, width: 3, height: 4),
             CGRect(x: 4.5, y: 4, width: 3, height: 8),
             CGRect(x: 9, y: 0, width: 3, height: 12)]

        // Two things overlapping.
        case .social:
            [CGRect(x: 0, y: 0, width: 8, height: 8),
             CGRect(x: 4, y: 4, width: 8, height: 8)]

        // Settled at the baseline.
        case .rest:
            [CGRect(x: 0, y: 8, width: 12, height: 4)]
        }
    }

    /// Only Creative carries the orange dot — it is the brand's own mark, and
    /// spending it once keeps it meaningful.
    private var dot: CGPoint? {
        kind == .creative ? CGPoint(x: 9, y: 0) : nil
    }
}

#Preview {
    HStack(spacing: 12) {
        ForEach(ActivityGlyph.Kind.allCases, id: \.self) { kind in
            ActivityGlyph(kind: kind, size: 24, color: .ink)
        }
    }
    .padding()
    .background(Color.canvas)
}
