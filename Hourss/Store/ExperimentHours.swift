import Foundation

/// The offer built from an hour this person has never logged.
///
/// **The source `PRD-HOURS.md` exists for.** Every other source reads something
/// other than the thing the app is actually about: `ExperimentVitals` reads heart
/// rate, which is a proxy for how a session felt; `ExperimentPriors` reads what is
/// ordinarily true of people, which is not about this person at all;
/// `ExperimentStarters` reads a Health fact about something else entirely. This one
/// reads their own ratings — the outcome every claim in the app is made of — and
/// uses them to name an hour they have not tried. That is why it sits above the
/// other three in the chain.
///
/// **It can only ever speak about the middle of somebody's day.** `RatingShape`
/// refuses any hour without evidence on both sides of it, so this source has nothing
/// to say to the person who logs only in the evening — and that is correct rather
/// than a shortfall. Their record contains no information about the morning, and the
/// sources below exist precisely for them: their body still knows something, and the
/// prior still has a question worth asking. §2 of the PRD draws that line and this
/// file sits entirely on one side of it.
enum ExperimentHours {

    /// Offers for the priorities a time-of-day test can serve, best hour first.
    static func proposals(
        for priorities: [Priority],
        shape: RatingShape.Shape,
        observations: [EngineObservation],
        wake: Int? = nil,
        measured: Set<String> = [],
        excluding: Set<String> = [],
        skipping: Set<Priority> = [],
        calendar: Calendar = .current
    ) -> [ExperimentDesign.Proposal] {
        // The same guard `ExperimentDesign.proposals`, `ExperimentStarters.build`
        // and `ExperimentVitals.proposals` all open with: nothing was said about
        // what matters, so there is no area to work on and this layer picks none on
        // somebody's behalf.
        guard !priorities.isEmpty, !shape.isEmpty else { return [] }

        let used = loggedHours(in: observations, calendar: calendar)
        var taken = excluding.union(measured)
        var out: [ExperimentDesign.Proposal] = []

        for (rank, priority) in priorities.enumerated() where !skipping.contains(priority) {
            // Which priorities a time-of-day test can serve is `Priority.insightTypes`'
            // decision, asked as a question about the type rather than written as a
            // `case`, so moving `bestTimeWindow` elsewhere moves this with it.
            guard priority.insightTypes.contains(.bestTimeWindow) else { continue }

            for candidate in candidates(shape: shape, used: used, wake: wake) {
                // The hour's own row, not its band's. The band row was what made this
                // source unreachable — anybody dense enough for a curve has every band
                // measured — and it was also the reason the change could only ask for
                // a band. `HourHypothesis` fixes both at once: the question is new, and
                // adherence counts the hour because `ExperimentOutcome` reads
                // `hypothesis.focus`.
                let hypothesis = HourHypothesis.make(hour: candidate.hour)
                guard !taken.contains(hypothesis.id) else { continue }
                taken.insert(hypothesis.id)
                out.append(proposal(hypothesis, at: candidate,
                                    band: TimeBucket.bucket(forHour: candidate.hour),
                                    priority: priority, rank: rank))
                break
            }
        }
        return out
    }

    /// Hour-led offers, then whatever was already going to be offered.
    ///
    /// The same shape `ExperimentVitals.completing` takes, and for the same reason:
    /// a priority already served by something measured keeps it, and a hypothesis
    /// already spoken for is not offered twice.
    static func completing(
        _ proposals: [ExperimentDesign.Proposal],
        priorities: [Priority],
        shape: RatingShape.Shape,
        observations: [EngineObservation],
        wake: Int? = nil,
        measured: Set<String> = [],
        excluding: Set<String> = []
    ) -> [ExperimentDesign.Proposal] {
        proposals + self.proposals(
            for: priorities,
            shape: shape,
            observations: observations,
            wake: wake,
            measured: measured,
            excluding: excluding.union(proposals.map(\.hypothesisId)),
            skipping: Set(proposals.map(\.priority))
        )
    }

    // MARK: - Choosing an hour

    /// Hours worth offering, best first.
    ///
    /// **Only hours they do not already use.** An offer to try an hour somebody
    /// already logs at is not an offer, and `RatingShape` deliberately keeps those
    /// hours in the curve — they are what the untried ones are read against.
    ///
    /// **Only hours they are awake for**, by the same gate `ExperimentVitals.ranked`
    /// applies, and open for the same reason when no waking time is known.
    ///
    /// **Both kinds of day, workdays first.** A workday offer reaches somebody five
    /// times a fortnight and a days-off offer four at most, so where both are
    /// available the workday one is the question that gets answered.
    static func candidates(
        shape: RatingShape.Shape,
        used: Set<Int>,
        wake: Int?
    ) -> [RatingShape.Hour] {
        let eligible = shape.hours.filter {
            !used.contains($0.hour) && WakeShape.isAwake(at: $0.hour, wake: wake)
        }
        let workdays = eligible.filter(\.isWorkday).sorted(by: better)
        let daysOff = eligible.filter { !$0.isWorkday }.sorted(by: better)
        return workdays + daysOff
    }

    /// Higher estimate first, earlier hour on a tie — the total order every other
    /// shape in this engine keeps, so two runs over one history offer the same hour.
    private static func better(_ left: RatingShape.Hour, _ right: RatingShape.Hour) -> Bool {
        if left.estimate != right.estimate { return left.estimate > right.estimate }
        return left.hour < right.hour
    }

    /// Every hour this person has actually logged a rated session in.
    static func loggedHours(
        in observations: [EngineObservation],
        calendar: Calendar = .current
    ) -> Set<Int> {
        Set(observations.compactMap { observation in
            observation.feeling == nil ? nil : calendar.component(.hour, from: observation.startAt)
        })
    }

    // MARK: - Assembly

    /// An hour and its band's registry row, as something somebody can accept.
    ///
    /// **`Standing.starter`, and the evidence fields are zero**, for the reason
    /// `ExperimentVitals.proposal` gives at length: nothing has been measured about
    /// how this band's sessions read, which is what the fortnight is for, so there is
    /// no effect to quote and no day count to quote it across.
    ///
    /// **The change asks for the hour, because the hour is what is measured.** The
    /// first version of this carried the band's row and asked for the band, on
    /// `ExperimentCopy.vitalsChange`'s argument that a change must ask for whatever
    /// adherence counts. That argument is right and it is satisfied here the other
    /// way round: the proposal carries `HourHypothesis`, whose focus is half an hour
    /// either side of the hour, so adherence counts the hour and the plain wording is
    /// the honest one. `PRD-HOURS.md` §10.3 records why the band version could never
    /// reach anybody.
    ///
        static func proposal(
        _ hypothesis: Hypothesis,
        at hour: RatingShape.Hour,
        band: TimeBucket,
        priority: Priority,
        rank: Int
    ) -> ExperimentDesign.Proposal {
        ExperimentDesign.Proposal(
            hypothesisId: hypothesis.id,
            outcome: hypothesis.outcome,
            type: hypothesis.type,
            standing: .starter,
            focusLabel: hypothesis.focusLabel,
            baselineLabel: hypothesis.baselineLabel,
            premise: ExperimentCopy.hoursPremise(hour: hour.hour, band: band,
                                                 isWorkday: hour.isWorkday),
            // Nil for the reason `ExperimentVitals.proposal` gives: here the evidence
            // *is* the premise, and the sentence immediately after it says nothing
            // logged settles the question. Splitting them would move the disclaimer
            // away from the claim it qualifies.
            context: nil,
            change: ExperimentCopy.hoursChange(hour: hour.hour, isWorkday: hour.isWorkday),
            caveat: hypothesis.caveat,
            priority: priority,
            priorityRank: rank,
            evidenceDays: 0,
            figure: 0,
            baselineFigure: 0
        )
    }
}
