import SwiftUI
import Observation

/// Which piece of UI a tour step points at.
enum TourTarget: Hashable {
    case searchBar, locationRow, phaseFilter        // trials list
    case firstResult
    case colourKey, requirements, siteLocation, questions, contactButton   // trial detail
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
        case colourKey, requirements, siteLocation, questions, contact
        // Back out
        case profileTab, savedTab, finish

        var target: TourTarget? {
            switch self {
            case .searchBar:    return .searchBar
            case .location:     return .locationRow
            case .phases:       return .phaseFilter
            case .pickCondition: return .searchBar
            case .openTrial:    return .firstResult
            case .colourKey:    return .colourKey
            case .requirements: return .requirements
            case .siteLocation: return .siteLocation
            case .questions:    return .questions
            case .contact:      return .contactButton
            // The tab steps open the real tab and show it whole — nothing to
            // mark, because the whole screen is the point.
            case .profileTab, .savedTab, .finish: return nil
            }
        }

        var title: String {
            switch self {
            case .searchBar:    return "Search by condition"
            case .location:     return "Where to look"
            case .phases:       return "Stage of testing"
            case .pickCondition: return "Let's try one"
            case .openTrial:    return "Open a trial"
            case .colourKey:    return "What the colours mean"
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
                return "Set your ZIP code or city, and how far you'd travel. Trials often need weekly visits, so distance matters more than people expect. Right now this is showing an example location."
            case .phases:
                return "Filter by how far along a treatment is. Each option explains what that stage actually means — a higher number isn't automatically better."
            case .pickCondition:
                return "Pick one below to see what results look like. This is just an example — you'll choose your own condition in a moment."
            case .openTrial:
                return "Tap on the provided trial to see what's inside."
            case .colourKey:
                return "Green means your details already satisfy that rule. Amber means we can't tell — it needs bloodwork or a doctor's judgement, so it's worth asking about. Red means the trial record rules you out, which only happens for age and sex. Most rules are amber, and that's normal."
            case .requirements:
                return "The rules themselves, split into requirements — things you need — and disqualifiers, things that would rule you out. Scroll through them; the list stays put."
            case .siteLocation:
                return "The nearest site that's still enrolling, and how many others there are. Sites can close while a trial keeps running elsewhere — we only point you at open ones."
            case .questions:
                return "Most rules need bloodwork or a doctor's judgement, so most stay amber. That's normal — this is your list for the conversation, not a verdict. Once you add your own details, the ones we can answer turn green."
            case .contact:
                return "Call or email the coordinator, with a message already drafted from your details. This is the step most people never take — and it's free, normal, and commits you to nothing."
            case .profileTab:
                return "Age, height, weight, and where you're searching from. You'll fill these in next, and can change them any time. Adding past treatments here later makes the question lists noticeably sharper."
            case .savedTab:
                return "Bookmark a trial and it waits for you here, even if you search for something else."
            case .finish:
                return "That's the whole app. Now let's set up your details, so the results are about you rather than this example."
            }
        }

        /// Interactive steps wait for the person to do something.
        var waitsForAction: Bool {
            self == .pickCondition || self == .openTrial
        }

        /// Steps where the person should be able to touch the app underneath —
        /// the requirements list is long, and describing it without letting
        /// anyone scroll it teaches very little.
        var allowsScrolling: Bool {
            self == .requirements
        }

        /// Which tab this step wants on screen.
        var tab: Int? {
            switch self {
            case .savedTab: return 1
            case .profileTab: return 2
            default: return 0
            }
        }

        var buttonLabel: String {
            self == .finish ? "Set up my details" : "Got it"
        }

        /// Which screen this step belongs on.
        var isOnDetailScreen: Bool {
            (Step.colourKey.rawValue...Step.contact.rawValue).contains(rawValue)
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

    /// Going back matters here: the walkthrough covers a lot in twelve steps,
    /// and someone who missed one otherwise has to abandon the whole thing.
    func retreat() {
        guard let current = step, current.rawValue > 0 else { return }
        step = Step(rawValue: current.rawValue - 1)
    }

    var canRetreat: Bool { (step?.rawValue ?? 0) > 0 }

    /// Called when the person completes an interactive step.
    func completed(_ action: Step) {
        guard step == action else { return }
        advance()
    }

    func skip() { step = nil }
}
