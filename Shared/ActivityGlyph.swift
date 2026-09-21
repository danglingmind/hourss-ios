import SwiftUI

/// A mark for each activity, drawn rather than borrowed.
///
/// These used to be eight arrangements of rectangles — one tall block for deep
/// work, three lines for admin, two overlapping squares for social — on the
/// principle that the system rules out borrowed iconography. They were coherent
/// and they were unreadable: nothing about three stacked rules says "admin" to
/// somebody who has not been told, and an icon that has to be explained is a
/// label in a worse typeface.
///
/// So they are pictographic now, and the discipline moved rather than
/// disappeared. Nothing here is an SF Symbol or a borrowed asset — every mark is
/// a path on a shared 24×24 grid at one stroke weight, so the eight still read as
/// one family and still belong to this system rather than to Apple's.
///
/// **Pixel alignment.** Every coordinate is snapped to the device pixel grid
/// before it is drawn (`px`). A 3-unit stroke on a 24 grid at 16pt is exactly
/// 2pt, but the *positions* land on thirds of a point, and a 2pt line straddling
/// a pixel boundary is rendered as two grey 1pt lines. Snapping is the difference
/// between a set that looks drawn and a set that looks blurred — and it matters
/// most at the small sizes, where these are mostly used.
struct ActivityGlyph: View {
    let kind: Kind
    var size: CGFloat = 16
    var color: Color = .lime

    /// 0…1, looping. Zero is the resting pose, which is what every static use
    /// renders — an icon in a list must not depend on being animated to be right.
    var phase: Double = 0

    /// Extra grid units above the 24×24 box, for a mark whose animation needs to
    /// arrive from somewhere. Canvas clips to its own frame, so without this a
    /// thing falling from above simply is not drawn until it is already home.
    ///
    /// Zero everywhere static, which keeps the square box and the exact drawing
    /// every list and Lock Screen already renders.
    var runway: CGFloat = 0

    @Environment(\.displayScale) private var displayScale

    enum Kind: String, CaseIterable {
        case deepWork, meetings, admin, learning, creative, exercise, social, rest

        /// Maps an activity name to its mark. Unknown activities fall back to the
        /// focus mark rather than inventing a glyph.
        ///
        /// The raw values are a stored format: `LiveSessionController` writes them
        /// into the Live Activity's attributes and the widget reads them back, so
        /// renaming a case silently blanks the icon on somebody's Lock Screen.
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
            var pen = GlyphPen(
                context: context,
                unit: canvasSize.width / 24,
                scale: displayScale,
                color: color,
                phase: phase,
                yShift: runway
            )
            pen.draw(kind)
        }
        .frame(width: size, height: size * (24 + runway) / 24)
        .accessibilityHidden(true)
    }
}

/// Draws one mark on a 24×24 grid, snapping everything to device pixels.
private struct GlyphPen {
    var context: GraphicsContext
    let unit: CGFloat
    let scale: CGFloat
    let color: Color
    let phase: Double
    /// Grid units of headroom above y=0. Every y passes through here, so a mark
    /// can use negative coordinates for "off the top" without knowing about it.
    var yShift: CGFloat = 0

    /// The one stroke weight the whole set is drawn at.
    static let weight: CGFloat = 3

    // MARK: - Grid

    /// A grid coordinate in points, snapped to a whole device pixel.
    private func px(_ value: CGFloat) -> CGFloat {
        let points = value * unit
        return (points * scale).rounded() / scale
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: px(x), y: px(y + yShift))
    }

    private func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        // Snapping the far edge rather than the width keeps a shape's two sides on
        // the grid; snapping a width independently lets rounding drift them apart.
        let minX = px(x), minY = px(y + yShift)
        return CGRect(x: minX, y: minY,
                      width: px(x + width) - minX,
                      height: px(y + height + yShift) - minY)
    }

    private func fill(_ path: Path, opacity: Double = 1) {
        context.fill(path, with: .color(color.opacity(opacity)))
    }

    private func fillRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, opacity: Double = 1) {
        fill(Path(rect(x, y, w, h)), opacity: opacity)
    }

    private func stroke(_ path: Path, width: CGFloat = GlyphPen.weight, opacity: Double = 1) {
        context.stroke(
            path,
            with: .color(color.opacity(opacity)),
            style: StrokeStyle(lineWidth: px(width), lineCap: .butt, lineJoin: .miter)
        )
    }

    private func polyline(_ points: [(CGFloat, CGFloat)]) -> Path {
        var path = Path()
        for (index, p) in points.enumerated() {
            let cg = point(p.0, p.1)
            index == 0 ? path.move(to: cg) : path.addLine(to: cg)
        }
        return path
    }

    private func closed(_ points: [(CGFloat, CGFloat)]) -> Path {
        var path = polyline(points)
        path.closeSubpath()
        return path
    }

    private func circle(centerX: CGFloat, centerY: CGFloat, radius: CGFloat) -> Path {
        Path(ellipseIn: rect(centerX - radius, centerY - radius, radius * 2, radius * 2))
    }

    /// A 0…1 phase as a smooth there-and-back, so no animation snaps when it loops.
    private var swell: Double { (1 - cos(phase * 2 * .pi)) / 2 }

    // MARK: - The set

    mutating func draw(_ kind: ActivityGlyph.Kind) {
        switch kind {
        case .deepWork: drawDeepWork()
        case .meetings: drawMeetings()
        case .admin: drawAdmin()
        case .learning: drawLearning()
        case .creative: drawCreative()
        case .exercise: drawExercise()
        case .social: drawSocial()
        case .rest: drawRest()
        }
    }

    /// A target: one ring and a solid core. Attention on a single thing.
    ///
    /// This was four corner brackets around a dot, which read as crop marks or a
    /// QR frame — eight separate pieces that fell apart at 14pt. A ring and a core
    /// is two pieces, survives any size, and actually says focus. It is distinct
    /// from `social` because that is two rings side by side and overlapping, where
    /// this is one ring, centred, around something solid.
    private mutating func drawDeepWork() {
        stroke(circle(centerX: 12, centerY: 12, radius: 9.5))
        fill(circle(centerX: 12, centerY: 12, radius: 3.5))

        // A second ring closes onto the core and fades as it arrives — locking on.
        // It is born out of nothing at rest, so the icon at phase 0 is just the
        // ring and the core.
        let travel = 9.5 - 5.5 * swell
        if swell > 0.01 {
            stroke(circle(centerX: 12, centerY: 12, radius: travel),
                   width: 2, opacity: 0.45 * (1 - swell))
        }
    }

    /// Two speech marks, angled towards each other. A conversation, not a calendar
    /// — the thing that makes a meeting a meeting is that somebody is talking.
    private mutating func drawMeetings() {
        // They alternate, so the emphasis passes back and forth like a turn being
        // taken. Opacity rather than movement: two bubbles jostling reads as noise.
        //
        // Built from the two halves of one sine so that *both* are solid at phase
        // 0. An alternation that simply crossfades leaves one bubble permanently
        // dimmed in every static use — which is most of them.
        let wave = sin(phase * 2 * .pi)
        let first = 1 - 0.4 * max(0, wave)
        let second = 1 - 0.4 * max(0, -wave)

        fillRect(0, 2, 14, 9, opacity: first)
        fill(closed([(3, 11), (3, 16), (8, 11)]), opacity: first)

        fillRect(10, 14, 14, 8, opacity: second)
        fill(closed([(21, 14), (21, 9), (16, 14)]), opacity: second)
    }

    /// A checklist, complete: three ticks and three rules.
    ///
    /// It used to draw the ticks landing one at a time, which meant the resting
    /// pose — the one every list, chip and Lock Screen renders — was a checklist
    /// two thirds undone. Everything is solid now, and the animation moves rows
    /// rather than revealing them.
    private mutating func drawAdmin() {
        let rows: [(CGFloat, CGFloat)] = [(2, 15), (10.5, 15), (19, 10)]
        for (index, row) in rows.enumerated() {
            let (y, length) = row
            // Each row is nudged in turn, a third of a cycle apart, so attention
            // walks down the list the way it does when you are working through one.
            let offset = (phase + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            let nudge = 0.9 * ((1 - cos(offset * 2 * .pi)) / 2)

            stroke(polyline([(0 + nudge, y + 1.5), (2.5 + nudge, y + 4), (6.5 + nudge, y - 0.5)]),
                   width: 2.5)
            fillRect(10 + nudge, y, length, 2.5)
        }
    }

    /// An open book, opening upward, with a page turning over the gutter.
    ///
    /// It used to open *downward*: the spine sat higher than the outer edges, so
    /// the top edge made a Λ and the whole thing read as a book held face down.
    /// Both edges dip toward the gutter now, which is the V an open book actually
    /// makes when you are looking into it.
    private mutating func drawLearning() {
        fill(closed([(1, 3), (11.2, 6), (11.2, 21), (1, 18)]))
        fill(closed([(12.8, 6), (23, 3), (23, 18), (12.8, 21)]))
        drawTurningPage()
    }

    /// One sheet lifting off the right leaf, over the gutter, and down onto the left.
    ///
    /// **Why it loops cleanly.** At either end of a turn the sheet lies exactly on
    /// top of a static leaf — same four corners — so it is invisible there, and the
    /// jump back to the right-hand side at the start of the next turn has nothing
    /// to see. That is also what keeps the resting pose honest: at `phase: 0` the
    /// sheet is not drawn at all, and the mark is just the book.
    ///
    /// **Why it looks like paper.** Three things, none of them an easing curve:
    ///
    /// - The turn is fast off the flick, slows as the sheet stands up, then falls
    ///   away quickly (`t + k·sin 2πt`). A page is a pendulum — it loses speed
    ///   climbing against gravity and gains it coming down the other side, so the
    ///   slow part belongs at the top rather than at both ends.
    /// - Its width is the cosine of the angle, because that is what a rotating
    ///   sheet projects. Foreshortening is most of what sells the rotation.
    /// - It bows sideways as it rises. A real sheet is not rigid, and without the
    ///   bow it would be exactly zero pixels wide at vertical and vanish for a
    ///   frame in the middle of every turn.
    private mutating func drawTurningPage() {
        // Two turns a cycle, so the book reads as being read rather than as
        // something that twitches every four seconds.
        let turn = (phase * 2).truncatingRemainder(dividingBy: 1)
        let eased = turn + 0.12 * sin(2 * .pi * turn)
        let angle = .pi * eased
        let rise = CGFloat(sin(angle))

        // Flat against a leaf: the static pages already draw exactly this.
        guard rise > 0.004 else { return }

        let lean = CGFloat(cos(angle))
        let hinge: CGFloat = 12
        // The sheet arcs well clear of the book, and needs the runway to do it.
        //
        // Held inside the square it is invisible, and not for want of shaping: a
        // page rotating about the gutter projects, in a flat front view, entirely
        // *within* the footprint of the leaf beneath it. Nothing about it can be
        // seen until it breaks the book's outline, so the arc has to be real.
        let lift = 9 * rise
        // The bow carries the sheet through the one moment it has no width of its
        // own. Edge-on, projection alone would leave nothing to draw, and a page
        // that disappears for a fifth of every turn reads as a dropped frame.
        let bow = -5.5 * rise

        let innerX = hinge + 0.8 * lean
        let outerX = hinge + 11 * lean
        let outerTop = 6 - 3 * abs(lean) - lift
        let outerBottom = 21 - 3 * abs(lean) - lift
        let midX = (innerX + outerX) / 2 + bow

        var page = Path()
        page.move(to: point(innerX, 6))
        page.addQuadCurve(to: point(outerX, outerTop),
                          control: point(midX, (6 + outerTop) / 2))
        page.addLine(to: point(outerX, outerBottom))
        page.addQuadCurve(to: point(innerX, 21),
                          control: point(midX, (21 + outerBottom) / 2))
        page.closeSubpath()

        fill(page)

        // The sheet's own edge, cut rather than drawn.
        //
        // Everything in a glyph is one colour, so a page lying on top of a leaf is
        // invisible however carefully it is shaped — the lift alone only exposed
        // the sliver that cleared the book's outline. Erasing a hairline along the
        // page's boundary lets the background through as a thin separation, which
        // is exactly what the edge of a raised sheet looks like. It widens with the
        // lift, so it is absent at the two moments the sheet lies flat and would
        // otherwise trace an outline around a leaf that is not moving.
        context.drawLayer { layer in
            layer.blendMode = .destinationOut
            layer.stroke(
                page,
                with: .color(.black),
                style: StrokeStyle(lineWidth: px(1.5 * rise), lineJoin: .round)
            )
        }
    }

    /// A spark, and the only mark carrying the brand's separated dot — spending it
    /// once, on the activity it means most for, keeps it meaningful.
    private mutating func drawCreative() {
        let reach = 1.5 * swell
        fill(closed([
            (11, 0), (13, 9 - reach), (22 + reach, 11), (13, 13 + reach),
            (11, 24), (9, 13 + reach), (0 - reach, 11), (9, 9 - reach),
        ]))

        // The dot keeps its own beat rather than the spark's, so the mark has two
        // things happening in it instead of one thing happening twice.
        let pulse = 0.6 + 0.4 * ((1 - cos((phase + 0.25) * 2 * .pi)) / 2)
        context.fill(
            circle(centerX: 20.5, centerY: 3.5, radius: 2.2 + 0.4 * pulse),
            with: .color(.orange.opacity(pulse))
        )
    }

    /// A dumbbell resting on the ground.
    ///
    /// The animation is one rep, and it loops without a seam because the reset is
    /// itself physical: the weight is thrown up and out of frame, then gravity
    /// brings it back down. Every other way of restarting a drop needs the object
    /// to teleport from the floor to the sky, which either pops or has to be
    /// hidden behind a fade that reads as a rendering bug.
    ///
    /// Both arcs are real motion rather than eased curves borrowed from a UI kit.
    /// The throw decelerates as it climbs (`2u - u²`) and the fall accelerates as
    /// it drops (`1 - u²`) — the same parabola run in both directions, which is
    /// what gravity actually does to a thrown object.
    private mutating func drawExercise() {
        let ground: CGFloat = 21
        let plateTop: CGFloat = 11, plateBottom: CGFloat = 21

        // Far enough that the weight clears the top of whatever canvas it is in,
        // so the hang at the top of the throw is genuinely off-screen.
        let height = yShift + 22

        // One rep, weighted so the drop is the event.
        //
        // The throw is quick and the apex has no hold at all: a hang reads as the
        // icon having gone missing, because at the top the weight is genuinely off
        // the canvas and all that is left on the card is a bare line. Reversal
        // happens at the apex, off-screen, so there is no seam to see.
        let lift = 0.50, drop = 0.60, land = 0.85
        var offset: CGFloat = 0
        var impact = 0.0

        switch phase {
        case ..<lift:
            offset = 0
        case ..<drop:
            let u = (phase - lift) / (drop - lift)
            offset = -height * (2 * u - u * u)     // thrown up, slowing as it climbs
        case ..<land:
            let u = (phase - drop) / (land - drop)
            offset = -height * (1 - u * u)          // falling, gathering speed
        default:
            offset = 0
            impact = (phase - land) / (1 - land)    // landed: dust and settle
        }

        // The ground takes the hit: it thickens on contact and recovers. The line
        // is the only thing that does not move, so it is the only thing that can
        // show the blow landing.
        let struck = impact > 0 ? (1 - impact) : 0
        fillRect(0, ground, 24, 2.5 + 1.4 * struck * struck)

        // A short squash on contact, recovering fast. Steel does not squash, but
        // the eye reads perfectly rigid impact as a missed frame.
        let squash = 1.4 * struck * struck
        let top = plateTop + offset + squash
        let bottom = plateBottom + offset

        fillRect(2, top, 4.5, bottom - top)
        fillRect(17.5, top, 4.5, bottom - top)
        let barTop = (top + bottom) / 2 - 1.5
        fillRect(6.5, barTop, 11, 3)

        // After the weight, not before. Drawn first, the burst is thrown from
        // under the plates and the plates are then filled straight over the top of
        // it — which is why the first pass looked like the dumbbell simply arrived.
        if impact > 0 { drawDust(progress: impact, ground: ground) }
    }

    /// Dust thrown out from under the weight: two bursts, out and up, thinning as
    /// they go and dragged back down.
    ///
    /// Each puff leaves on its own angle — the low ones skim the floor, the high
    /// ones are thrown up and fall back. Sending them all along the ground, which
    /// is what the first version did, put every puff inside the ground line; the
    /// line is the same colour, so the burst read as the floor having grown lumps.
    private mutating func drawDust(progress: Double, ground: CGFloat) {
        let fade = 1 - progress
        guard fade > 0.02 else { return }

        // Fast out of the blow, easing off hard — dust is thrown, not blown.
        let travel = CGFloat(progress) * (1.8 - CGFloat(progress) * 0.8)
        // Gravity, on the dust as much as on the weight that threw it.
        let drag = CGFloat(9) * CGFloat(progress * progress)

        for side in [CGFloat(-1), 1] {
            // The outer edge of each plate, so the burst clears the weight rather
            // than starting underneath it.
            let origin: CGFloat = side < 0 ? 2 : 22

            for index in 0..<4 {
                let angle = (12 + Double(index) * 21) * .pi / 180
                let distance = (7 + CGFloat(index) * 1.5) * travel
                let radius = max(0.15, (2.4 - CGFloat(index) * 0.4) * CGFloat(fade))

                let x = origin + side * distance * CGFloat(cos(angle))
                // Clear of the line from the first frame, so the burst is never
                // drawn inside the thing it is bouncing off.
                let y = ground - 1.5 - distance * CGFloat(sin(angle)) + drag

                context.fill(
                    circle(centerX: x, centerY: y, radius: radius),
                    with: .color(color.opacity(fade * 0.85))
                )
            }
        }
    }

    /// Two rings overlapping: the part of the time that is shared.
    private mutating func drawSocial() {
        // They breathe together and apart. The overlap is the subject, so the
        // travel is small enough to keep it always present.
        let apart = 0.9 * swell
        let radius: CGFloat = 7.5
        stroke(circle(centerX: 8 - apart, centerY: 12, radius: radius))
        stroke(circle(centerX: 16 + apart, centerY: 12, radius: radius))
    }

    /// A crescent. Rest is the one activity the app also reads from Health, where
    /// it arrives as a night.
    private mutating func drawRest() {
        // Cut from a disc rather than drawn as a shape, so the inner edge is a true
        // arc and the two curves stay concentric at every size.
        let close = 1.2 * swell
        context.drawLayer { layer in
            layer.clip(
                to: circle(centerX: 17 + close, centerY: 8 - close, radius: 10),
                options: .inverse
            )
            layer.fill(circle(centerX: 11, centerY: 12, radius: 11), with: .color(color))
        }
    }
}

extension ActivityGlyph.Kind {
    /// How much room above the box this mark's animation needs.
    ///
    /// Two marks leave their square: the weight falls into it, and the page arcs
    /// over the top of the book. Everything else animates within its own box, and
    /// giving them headroom they do not use would push them off centre wherever
    /// they are placed.
    var runway: CGFloat {
        switch self {
        case .exercise: 26
        case .learning: 10
        default: 0
        }
    }
}

/// The mark, alive.
///
/// Used on the running-session card, where the icon is the only thing on screen
/// that moves — so each animation is the activity's own gesture rather than a
/// generic pulse: attention narrowing, a turn being taken, a page lifting, a
/// reading running along a trace.
///
/// Reduce Motion gets the resting pose, which is a real icon rather than a
/// degraded one, because `phase: 0` is what every static use already renders.
struct AnimatedActivityGlyph: View {
    let kind: ActivityGlyph.Kind
    var size: CGFloat = 64
    var color: Color = .lime
    /// One full cycle. Slow on purpose: this sits beside a running clock, and an
    /// icon that draws the eye away from the number is doing harm.
    var period: Double = 4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            ActivityGlyph(kind: kind, size: size, color: color)
        } else {
            // 30fps rather than the display's full rate. A session runs for hours
            // with this on screen, and nothing here is fast enough to need 120.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                ActivityGlyph(
                    kind: kind,
                    size: size,
                    color: color,
                    phase: phase(at: context.date),
                    runway: kind.runway
                )
            }
            // Layout reserves the square the icon actually occupies; the runway
            // overflows upward and is drawn over whatever is above it. That is the
            // point — the weight has to come from outside the card, not from
            // inside a box that quietly got taller.
            .frame(width: size, height: size, alignment: .bottom)
        }
    }

    private func phase(at date: Date) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        return elapsed / period
    }
}

#Preview("The set") {
    VStack(spacing: 24) {
        ForEach([CGFloat(14), 24, 48], id: \.self) { size in
            HStack(spacing: 16) {
                ForEach(ActivityGlyph.Kind.allCases, id: \.self) { kind in
                    ActivityGlyph(kind: kind, size: size, color: .ink)
                }
            }
        }
    }
    .padding()
    .background(Color.canvas)
}

#Preview("Animated") {
    HStack(spacing: 20) {
        ForEach(ActivityGlyph.Kind.allCases, id: \.self) { kind in
            AnimatedActivityGlyph(kind: kind, size: 44, color: .lime)
        }
    }
    .padding()
    .background(Color.forest)
}
