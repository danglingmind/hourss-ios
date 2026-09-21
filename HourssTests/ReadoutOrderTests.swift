import Testing
import Foundation
@testable import Hourss

/// Every readout names its subject before it states its figure.
///
/// The complaint this suite exists to hold: "at a glance all I notice is a number
/// and I need to read to find out what this is about." A figure alone is not
/// information — "12%" means nothing until you know it is about sleep — so the
/// fix is an ordering rule, and an ordering rule is exactly the kind of thing
/// that rots silently. Nothing here looks at pixels; it tests the values the
/// screens are built from, which is why the readouts were split into a subject
/// and a figure in the first place.
@Suite("Readouts name their subject first")
@MainActor
struct ReadoutOrderTests {

    /// A subject is a name. If the top step opens with a digit, the readout has
    /// put its figure back in the slot this whole change moved it out of.
    private func expectNamesFirst(_ title: String, _ spoken: String) {
        #expect(!title.isEmpty, "a readout with no subject is the original bug")
        #expect(title.first?.isNumber != true,
                Comment(rawValue: "a readout title opens with a digit: \(title)"))
        #expect(spoken.hasPrefix(title),
                Comment(rawValue: "spoken form does not lead with its subject: \(spoken)"))
    }

    // `TitledFigure`'s own contract is covered in `TitledFigureTests`; what
    // follows is the ordering of the readouts that call it, and of the ones too
    // compact to use it.

    // MARK: - Patterns, warming up

    @Test("The warm-up readout counts days and says so before counting them")
    func evidenceReadoutNamesDaysFirst() {
        #expect(EvidenceReadout.title == "Days with a rating")
        #expect(EvidenceReadout.figure(days: 3) == "3 of 12")
        #expect(EvidenceReadout.figure(days: 0) == "0 of 12")
        // The floor is the engine's condition, not a product heuristic, so the
        // figure has to be measured against `EvidenceFloor` and not a constant.
        #expect(EvidenceReadout.figure(days: 3).hasSuffix("of \(EvidenceFloor.days)"))

        // Composed the way Patterns composes it, so the screen's own reading
        // order is what is being asserted.
        let readout = TitledFigure(
            title: EvidenceReadout.title,
            figure: EvidenceReadout.figure(days: 3)
        )
        #expect(readout.spoken == "Days with a rating. 3 of 12")
        expectNamesFirst(readout.title, readout.spoken)
    }

    @Test("The warm-up readout carries no instruction and no countdown")
    func evidenceReadoutStaysPlain() {
        let text = (EvidenceReadout.title + " " + EvidenceReadout.figure(days: 3)).lowercased()
        for phrase in ["until", "days left", "days to go", "try", "keep logging",
                       "more data", "unlock", "locked", "yet", "soon", "average"] {
            #expect(!text.contains(phrase), Comment(rawValue: "'\(phrase)' in the warm-up readout: \(text)"))
        }
    }

    // MARK: - The energy reading

    @Test("A score is spoken after the session it belongs to")
    func energyReadingLeadsWithTheActivity() {
        let reading = EnergyReading(score: 87, caption: "Running", note: "45m, energizing.")
        expectNamesFirst("Running", reading.spoken)
        // Spelled, not punctuated: "87/100" is announced as "87 slash 100".
        #expect(reading.spoken.contains("87 out of 100"))
        // Colour is never the only carrier: the feeling word is spoken too.
        #expect(reading.spoken.contains("energizing"))
    }

    @Test("An unrated session still names itself first")
    func energyReadingUnrated() {
        let reading = EnergyReading(score: nil, caption: "Yoga", note: "30m. You haven't said how this one felt.")
        expectNamesFirst("Yoga", reading.spoken)
        #expect(reading.spoken.contains("Not rated"))
    }

    // MARK: - The journal's day rows

    @Test("A day row says what was done before how long it took")
    func daySummaryNamesActivitiesFirst() {
        let line = DaySummaryLine(activityNames: ["Running", "Yoga", "Running"], minutes: 90)
        #expect(line.names == "Running, Yoga")
        #expect(line.total == "1h 30m")
        #expect(line.spoken == "Running, Yoga, 1h 30m")
        expectNamesFirst(line.names, line.spoken)
    }

    @Test("A day row shows at most three names, alphabetically")
    func daySummaryCapsItsNames() {
        let line = DaySummaryLine(
            activityNames: ["Yoga", "Running", "Cycling", "Admin", "Reading"],
            minutes: 45
        )
        #expect(line.names == "Admin, Cycling, Reading")
        #expect(line.total == "45m")
    }

    @Test("A sub-minute day keeps a figure rather than showing a bare zero")
    func daySummaryHandlesShortDays() {
        let line = DaySummaryLine(activityNames: ["Reading"], minutes: 0)
        #expect(line.total == "<1m")
        expectNamesFirst(line.names, line.spoken)
    }
}
