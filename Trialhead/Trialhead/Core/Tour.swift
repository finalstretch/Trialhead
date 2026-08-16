import SwiftUI
import Observation

/// Which piece of UI a tour step points at.
enum TourTarget: Hashable {
    case searchBar, locationRow, phaseFilter        // trials list
    case firstResult
    case requirements, siteLocation, questions, contactButton   // trial detail
    case tabBar
}

/// The guided walkthrough that runs once, straight after onboarding.
///
/// Two interactive steps sit in the middle — pick a condition, then open a
/// trial. Reading about a feature and using it are different things, and the
/// tour is worth little if the person never touches anything.
@Observable
final class Tour {

    enum Step: Int, CaseIterable {
        // On the trials list
        case searchBar, location, phases
        case pickCondition          // interactive
        case openTrial              // interactive
        // On a trial's page
        case requirements, siteLocation, questions, contact
        // Back out
        case profileTab, savedTab, finish

        var target: TourTarget? {
            switch self {
            case .searchBar:    return .searchBar
            case .location:     return .locationRow
            case .phases:       return .phaseFilter
            case .pickCondition: return .searchBar
            case .openTrial:    return .firstResult
            case .requirements: return .requirements
            case .siteLocation: return .siteLocation
            case .questions:    return .questions
            case .contact:      return .contactButton
            case .profileTab, .savedTab: return .tabBar
            case .finish:       return nil
            }
        }

        var title: String {
            switch self {
            case .searchBar:    return "Search by condition"
            case .location:     return "Where to look"
            case .phases:       return "Stage of testing"
            case .pickCondition: return "Let's try one"
            case .openTrial:    return "Open a trial"
            case .requirements: return "The trial's requirements"
            case .siteLocation: return "Where it happens"
            case .questions:    return "Questions to ask"
            case .contact:      return "Contact the study team"
            case .profileTab:   return "Your details live here"
            case .savedTab:     return "Trials you've bookmarked"
            case .finish:       return "You're ready"
            }
        }

        var body: String {
            switch self {
            case .searchBar:
                return "Type the condition you're looking for trials for. You can change it any time."
            case .location:
                return "Set your ZIP code or city, and how far you'd travel. Trials often need weekly visits, so distance matters more than people expect."
            case .phases:
                return "Filter by how far along a treatment is. Each option explains what that stage actually means — a higher number isn't automatically better."
            case .pickCondition:
                return "Pick one below to see what results look like."
            case .openTrial:
                return "Tap any trial in the list to see what's inside."
            case .requirements:
                return "Every trial has pages of eligibility rules. We split them into requirements and disqualifiers. Green means you likely meet it; amber means it's worth asking about."
            case .siteLocation:
                return "The nearest site that's still enrolling, and how many others there are. Sites can close while a trial keeps running elsewhere — we only point you at open ones."
            case .questions:
                return "Most rules need bloodwork or a doctor's judgement, so most will be amber. That's normal. This is your list for the conversation, not a verdict on whether you qualify."
            case .contact:
                return "Call or email the coordinator, with a message already drafted from your details. This is the step most people never take — and it's free, normal, and commits you to nothing."
            case .profileTab:
                return "Change your age, height and weight here. You can also add past treatments and medications, which makes the question lists noticeably sharper."
            case .savedTab:
                return "Bookmark a trial and it waits for you here, even if you search for something else."
            case .finish:
                return "Search for any condition and start looking. You can always come back to Profile to fill in more details."
            }
        }

        /// Interactive steps wait for the person to do something.
        var waitsForAction: Bool {
            self == .pickCondition || self == .openTrial
        }

        var buttonLabel: String {
            self == .finish ? "Start looking" : "Got it"
        }

        /// Which screen this step belongs on.
        var isOnDetailScreen: Bool {
            (Step.requirements.rawValue...Step.contact.rawValue).contains(rawValue)
        }
    }

    /// Suggested conditions for the interactive step — common, and each returns
    /// plenty of trials in most US cities, so the demo doesn't fall flat.
    static let sampleConditions = [
        "Breast cancer", "Type 2 diabetes", "Alzheimer's disease",
        "Asthma", "Parkinson's disease",
    ]

    private(set) var step: Step?

    var isRunning: Bool { step != nil }

    func start() { step = .searchBar }

    func advance() {
        guard let current = step else { return }
        if current == .finish { step = nil; return }
        step = Step(rawValue: current.rawValue + 1)
    }

    /// Called when the person completes an interactive step.
    func completed(_ action: Step) {
        guard step == action else { return }
        advance()
    }

    func skip() { step = nil }
}
