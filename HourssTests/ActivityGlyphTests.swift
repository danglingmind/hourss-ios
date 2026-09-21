import Testing
import SwiftUI
import UIKit
@testable import Hourss

/// The activity marks.
///
/// Icons are a visual judgement and mostly cannot be asserted. Two things about
/// them can be, and both have already gone wrong once: the identifiers they are
/// stored under, and whether a mark is complete when nothing is animating it.
@Suite("Activity glyphs")
@MainActor
struct ActivityGlyphTests {

    /// `LiveSessionController` writes these raw values into the Live Activity's
    /// attributes and the widget reads them back out, so they are a stored format
    /// rather than an implementation detail. Renaming a case blanks the icon on
    /// somebody's Lock Screen, silently, for the length of their session.
    @Test("The stored identifiers never move")
    func rawValuesAreStable() {
        #expect(Set(ActivityGlyph.Kind.allCases.map(\.rawValue)) == [
            "deepWork", "meetings", "admin", "learning", "creative", "exercise", "social", "rest",
        ])
    }

    /// Every activity in the starter set has a mark of its own — a set where two
    /// activities share an icon is a set that cannot be read.
    @Test("Every starter activity maps to a distinct mark")
    func starterActivitiesAreCovered() {
        let kinds = Activity.defaults.map { ActivityGlyph.Kind.forActivity(named: $0.name) }
        #expect(kinds.count == Activity.defaults.count)
        #expect(Set(kinds).count == Activity.defaults.count, "Two activities share a mark")
    }

    @Test("An activity nobody recognises still gets a mark")
    func unknownActivitiesFallBack() {
        #expect(ActivityGlyph.Kind.forActivity(named: "Gardening") == .deepWork)
    }

    /// Drawing must not trap. `rest` builds its crescent with an inverse clip
    /// inside a layer, and `exercise` interpolates along a polyline — both are the
    /// kind of thing that divides by zero at a degenerate size.
    @Test("Every mark draws at every size, animating or still",
          arguments: ActivityGlyph.Kind.allCases)
    func everyMarkDraws(_ kind: ActivityGlyph.Kind) throws {
        for size in [CGFloat(14), 16, 24, 64] {
            for phase in [0.0, 0.25, 0.5, 0.75, 0.999] {
                let renderer = ImageRenderer(
                    content: ActivityGlyph(kind: kind, size: size, color: .ink, phase: phase)
                        .environment(\.displayScale, 3)
                )
                renderer.scale = 3
                #expect(renderer.uiImage != nil, "\(kind.rawValue) failed at \(size)pt, phase \(phase)")
            }
        }
    }

    /// The rule the set is built on, and the one it broke.
    ///
    /// `phase: 0` is what every list, chip and Lock Screen renders, so it has to be
    /// the finished mark. Three of these were animating *into* completeness —
    /// admin drew two of its three rows faint, exercise drew its whole trace at
    /// 28% and lit it up as the animation passed, meetings left a bubble dimmed —
    /// which meant the icon nearly everybody saw was the unfinished one.
    ///
    /// Measuring total ink cannot catch that: `creative` legitimately has *more*
    /// ink mid-animation, because its points reach outward. What separates the two
    /// is opacity. A finished mark is drawn solid, so its only part-transparent
    /// pixels are the antialiased edges; a mark with a dimmed region has whole
    /// areas sitting at a fraction of full, and those areas swamp the edges.
    @Test("Nothing in a still mark is drawn faint",
          arguments: ActivityGlyph.Kind.allCases)
    func restingPoseIsDrawnSolid(_ kind: ActivityGlyph.Kind) throws {
        // Named apart from the function: a local called `coverage` shadows it.
        let measured = try #require(coverage(kind, phase: 0))

        // Edges are unavoidable and the set is full of curves and diagonals, so
        // the bar is "soft pixels must not outweigh solid ones" rather than any
        // claim of being edge-free. The bugs this exists for ran to two and three
        // times this much.
        #expect(measured.soft < measured.solid, Comment(rawValue:
            "\(kind.rawValue) at rest has \(Int(measured.soft)) faint pixels against "
            + "\(Int(measured.solid)) solid — something in it is drawn dimmed, and the "
            + "still icon is the one nearly everybody sees"))
    }

    /// Pixels drawn at full strength, and pixels drawn part-way.
    private func coverage(_ kind: ActivityGlyph.Kind, phase: Double) -> (solid: Double, soft: Double)? {
        let side = 64
        let renderer = ImageRenderer(
            content: ActivityGlyph(kind: kind, size: CGFloat(side), color: .ink, phase: phase)
                .environment(\.displayScale, 1)
        )
        renderer.scale = 1
        guard let image = renderer.uiImage, let cgImage = image.cgImage else { return nil }

        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var solid = 0.0, soft = 0.0
        for index in stride(from: 3, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index]) / 255
            if alpha >= 0.88 { solid += 1 } else if alpha > 0.12 { soft += 1 }
        }
        return (solid, soft)
    }
}
