import Foundation

// Stage 2: decide what KIND of rule each criterion is.
// Pure keyword matching — no model, no network. DESIGN.md §7.

enum Category: String, CaseIterable {
    case age
    case sex
    case bmi
    case pregnancy
    case consent
    case performanceStatus
    case labValue
    case priorTherapy
    case diagnosis
    case other

    /// Human label for the UI and reports.
    var label: String {
        switch self {
        case .performanceStatus: return "performance status"
        case .priorTherapy:      return "prior treatment"
        case .labValue:          return "lab value"
        case .bmi:               return "BMI"
        default:                 return rawValue
        }
    }
}

enum Categorizer {

    /// Checked in order — first match wins, so the most specific patterns
    /// must come first. "Adults aged 18+ who are not pregnant" should land on
    /// pregnancy rather than age, because pregnancy is the checkable part.
    private static let rules: [(Category, [String])] = [
        (.pregnancy, ["pregnan", "lactat", "breastfeed", "breast-feed", "breast feeding",
                      "contracept", "childbearing", "birth control"]),

        (.performanceStatus, ["ecog", "karnofsky", "performance status", "who ps"]),

        (.labValue, ["hemoglobin", "haemoglobin", "creatinine", "platelet", "bilirubin",
                     "neutrophil", "leukocyte", "white blood cell", "albumin", "transaminase",
                     "hba1c", "uln", "upper limit of normal", "clearance", "mg/dl", "g/dl",
                     "mmol", "×10", "x10", "iu/l", "u/l", "organ function", "bone marrow function",
                     "laboratory value", "blood count"]),

        (.bmi, ["bmi", "body mass index"]),

        (.consent, ["informed consent", "written consent", "willing to comply",
                    "able to comply", "willing and able", "sign consent",
                    "provide consent", "study procedures"]),

        (.priorTherapy, ["prior ", "previous", "previously", "treated with", "pretreat",
                         "pre-treat", "refractory to", "naive", "has received", "have received",
                         "received treatment", "washout", "relapsed after"]),

        (.diagnosis, ["diagnos", "histologically", "cytologically", "confirmed",
                      "documented", "biopsy", "stage i", "stage ii", "stage iii", "stage iv",
                      "metastatic", "advanced"]),
    ]

    /// Short words that need whole-word matching. Without this, "male" matches
    /// inside "female" and every sex rule comes out wrong.
    private static let wholeWordRules: [(Category, [String])] = [
        (.sex, ["male", "males", "female", "females", "man", "men", "woman", "women"]),
        (.age, ["age", "aged", "ages", "years", "year", "old", "adult", "adults", "adolescent"]),
    ]

    /// Words signalling that a rule is about treatment *history* rather than
    /// current state — used to break ties when a rule mentions both.
    private static let historyMarkers = ["prior", "previous", "received", "treated",
                                         "refractory", "naive", "relapsed", "after"]

    static func categorize(_ text: String, profile: Profile) -> Category {
        let lower = text.lowercased()

        // Strongest signal available: the person's OWN words appear in the rule.
        // Beats every generic keyword below — a rule naming their exact diagnosis
        // is a diagnosis rule whether or not it says "histologically confirmed".
        let namesTreatment = profile.treatmentTerms.contains { lower.contains($0) }
        let namesCondition = profile.conditionTerms.contains { lower.contains($0) }
        let soundsHistorical = historyMarkers.contains { lower.contains($0) }

        if namesTreatment && (soundsHistorical || !namesCondition) { return .priorTherapy }
        if namesCondition { return .diagnosis }

        // Sex and age first — they're the only categories that can produce a
        // firm "no", so getting them right matters most.
        for (category, words) in wholeWordRules where words.contains(where: { containsWord($0, in: lower) }) {
            // "Age" language shows up inside pregnancy and consent rules a lot
            // ("women of childbearing age"), so let those win if they also match.
            if category == .age || category == .sex {
                if let stronger = firstSubstringMatch(lower), stronger == .pregnancy || stronger == .consent {
                    return stronger
                }
            }
            return category
        }

        return firstSubstringMatch(lower) ?? .other
    }

    private static func firstSubstringMatch(_ lower: String) -> Category? {
        for (category, needles) in rules where needles.contains(where: { lower.contains($0) }) {
            return category
        }
        return nil
    }

    /// Matches a word only when it stands alone — "male" in "male patients"
    /// but not "male" inside "female".
    private static func containsWord(_ word: String, in text: String) -> Bool {
        text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b",
                   options: [.regularExpression]) != nil
    }
}
