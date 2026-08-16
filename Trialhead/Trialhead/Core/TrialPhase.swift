import Foundation

/// The stage of testing a trial is at, with an explanation a non-clinician can
/// act on. The raw values are what the API returns in `designModule.phases`.
///
/// The app's user is a frightened caregiver, not a researcher. "Phase 1" on its
/// own is vocabulary; "first testing in people, mainly checking safety" is
/// information.
enum TrialPhase: String, CaseIterable, Codable, Identifiable {
    case earlyPhase1 = "EARLY_PHASE1"
    case phase1 = "PHASE1"
    case phase2 = "PHASE2"
    case phase3 = "PHASE3"
    case phase4 = "PHASE4"
    case notApplicable = "NA"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .earlyPhase1:   return "Early Phase 1"
        case .phase1:        return "Phase 1"
        case .phase2:        return "Phase 2"
        case .phase3:        return "Phase 3"
        case .phase4:        return "Phase 4"
        case .notApplicable: return "No phase"
        }
    }

    /// Short form for cards, where space is tight.
    var shortLabel: String {
        self == .notApplicable ? "No phase" : label
    }

    var blurb: String {
        switch self {
        case .earlyPhase1:
            return "A handful of people given very small doses, just to see how the body handles it. Uncommon."
        case .phase1:
            return "The first testing in people — usually 20 to 100. Mainly about safety and finding the right dose. Almost everyone gets the real treatment."
        case .phase2:
            return "Does it actually work? Around 100 to 300 people who have the condition. Most treatments stop here."
        case .phase3:
            return "A large study comparing it against today's standard treatment, often across many hospitals. The stage before approval."
        case .phase4:
            return "The treatment is already approved. These track long-term effects and rarer side effects."
        case .notApplicable:
            return "Not a drug trial. Studies of devices, surgery, exercise or counselling have no phase — it isn't missing information."
        }
    }

    /// Trials list `phases` as an array, and some studies carry none at all.
    /// An empty list means "no phase", not "unknown".
    static func keys(from phases: [String]?) -> [String] {
        let listed = (phases ?? []).filter { !$0.isEmpty }
        return listed.isEmpty ? [TrialPhase.notApplicable.rawValue] : listed
    }

    /// Display text for a card — "Phase 1/2" for combined studies.
    static func display(_ phases: [String]) -> String {
        let known = phases.compactMap { TrialPhase(rawValue: $0) }
        guard !known.isEmpty else { return notApplicable.shortLabel }
        if known.count == 1 { return known[0].shortLabel }
        // "Phase 1/2" reads better than "Phase 1/Phase 2".
        let numbers = known.compactMap { phase -> String? in
            switch phase {
            case .phase1: return "1"
            case .phase2: return "2"
            case .phase3: return "3"
            case .phase4: return "4"
            default: return nil
            }
        }
        return numbers.isEmpty ? known.map(\.shortLabel).joined(separator: "/")
                               : "Phase " + numbers.joined(separator: "/")
    }
}
