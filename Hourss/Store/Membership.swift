import Foundation
import Observation

/// The one place the app asks whether this person is entitled.
///
/// There is no StoreKit yet and nothing here pretends otherwise. What exists is
/// the question — `isEntitled` — held in a single object, so the surface that
/// varies on it can be built and both of its states tested before there is
/// anything to buy. When purchasing arrives it replaces how `tier` is set and
/// nothing that reads it has to move.
///
/// A singleton rather than an environment value: the two screens that need it,
/// Today and You, are reached through a root neither of them owns, and an
/// entitlement that two views could disagree about is not an entitlement.
@Observable
@MainActor
final class Membership {

    /// What the app reads. Tests build their own instances against a scratch
    /// defaults suite instead.
    static let shared = Membership()

    private let defaults: UserDefaults
    private static let storageKey = "hourss.membership.tier"

    private(set) var tier: Tier

    /// The only question anything outside this file should be asking.
    var isEntitled: Bool { tier.isEntitled }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var resolved = Self.persistedTier(in: defaults)
        #if DEBUG
        // A launch argument so a UI test can start in either state without first
        // driving the settings screen — otherwise every assertion about Today's
        // slot would be coupled to the row in You that switches the tier.
        if let forced = Self.launchArgumentTier { resolved = forced }
        #endif
        tier = resolved
    }

    /// Reads the stored tier, deliberately refusing anything that arrived on the
    /// command line.
    ///
    /// `UserDefaults` searches `NSArgumentDomain` ahead of everything persisted,
    /// so a plain `string(forKey:)` would make `-hourss.membership.tier member`
    /// a working entitlement grant in *any* build, shipped one included. The
    /// override below is `#if DEBUG`; this read has to be, in effect, the same,
    /// or the compile-time gate would guard the front door while the argument
    /// domain held the back one open.
    private static func persistedTier(in defaults: UserDefaults) -> Tier {
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        guard arguments[storageKey] == nil else { return .free }
        return defaults.string(forKey: storageKey).flatMap(Tier.init(rawValue:)) ?? .free
    }

    #if DEBUG
    /// The only writer, and it exists only in debug builds.
    ///
    /// The gate is on the mutation rather than on its callers. Gating the row in
    /// You would leave this method compiled into the shipped binary and callable
    /// by anything that could reach the object; gating the method means a release
    /// build contains no code path that grants entitlement at all. When StoreKit
    /// lands its writer sits beside this one, outside the `#if`, and is driven by
    /// a verified transaction rather than by a tap.
    func setTier(_ tier: Tier) {
        self.tier = tier
        defaults.set(tier.rawValue, forKey: Self.storageKey)
    }

    /// `-hourss-debug-tier member`. Read straight from `ProcessInfo` rather than
    /// through `UserDefaults`, so that the argument that overrides entitlement is
    /// a different name from the one that stores it and the guard above stays
    /// unambiguous.
    private static var launchArgumentTier: Tier? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-hourss-debug-tier"),
              index + 1 < arguments.count else { return nil }
        return Tier(rawValue: arguments[index + 1])
    }
    #endif
}

extension Tier {

    /// How the tier is named to the person whose tier it is. Plain state, not a
    /// pitch: You is a settings list and the row is telling them where they stand.
    var settingsDetail: String {
        switch self {
        case .free: "Free"
        case .member: "Member"
        }
    }
}

extension HourssStore {

    /// Entitlement, reachable the same way the evidence count is.
    ///
    /// The store does not own it — membership outlives any particular store and a
    /// test can hold its own — but everything that varies on entitlement already
    /// holds the store, and a second lookup route is a second thing to keep in
    /// step.
    var membership: Membership { .shared }

    /// Distinct calendar days carrying at least one rated session.
    ///
    /// Days, not sessions, because days are what the engine counts: it requires
    /// six distinct days on each side of a comparison, and six sessions on one
    /// Tuesday are one day of evidence about Tuesdays.
    ///
    /// The filter is `isEligibleForPatterns` and a present feeling score, which is
    /// exactly the row set `ObservationBuilder` hands the engine minus the ones no
    /// feeling hypothesis can use. A figure computed on any looser basis would
    /// count evidence the engine will never see.
    ///
    /// Distinct from `sessionsNeededForPatterns`, which counts sessions against a
    /// product heuristic of twelve. That figure still drives the warm-up screen
    /// and is not this one; PRD A.11 records the disagreement and asks for the two
    /// to be reconciled onto days.
    var ratedDayCount: Int {
        let calendar = Calendar.current
        var days: Set<Date> = []
        for session in sessions where session.isEligibleForPatterns {
            guard feeling(for: session.id) != nil else { continue }
            days.insert(calendar.startOfDay(for: session.startAt))
        }
        return days.count
    }

    /// Whether enough days have been gathered for any comparison to be possible.
    ///
    /// A necessary condition and never a sufficient one: clearing the floor makes
    /// a claim testable, not true, and nothing reading this may phrase it as an
    /// arrival.
    var meetsEvidenceFloor: Bool { ratedDayCount >= EvidenceFloor.days }
}
