import Foundation

// Stage 3: compare each rule against the profile and assign a verdict.
// DESIGN.md Principle 4 — when uncertain, always `.ask`, never `.blocker`.
// Wrongly telling someone they're disqualified could stop them pursuing a
// trial that would have helped them. "Worth asking about" costs nothing.

enum Verdict: String {
    case match      // 🟢 clearly satisfied
    case ask        // 🟠 can't tell — bring it to the care team
    case blocker    // 🔴 clearly not satisfied

    var glyph: String {
        switch self {
        case .match: return "🟢"
        case .ask: return "🟠"
        case .blocker: return "🔴"
        }
    }
}

struct EvaluatedCriterion {
    let criterion: Criterion
    let category: Category
    let verdict: Verdict
    let rationale: String
}

struct StructuredCheck {
    let label: String
    let verdict: Verdict
    let rationale: String
}

struct TrialEvaluation {
    let structured: [StructuredCheck]
    let criteria: [EvaluatedCriterion]

    var matches: Int { count(.match) }
    var asks: Int { count(.ask) }
    var blockers: Int { count(.blocker) }

    /// Headings are structural labels, not questions — counting them inflates
    /// the number shown on every card.
    private func count(_ v: Verdict) -> Int {
        criteria.filter { $0.verdict == v && !$0.criterion.isHeading }.count
            + structured.filter { $0.verdict == v }.count
    }
}

enum Evaluator {

    /// Only the structured API fields can produce a red verdict. They're exact
    /// numbers straight from the trial record, not guesses from parsed prose —
    /// so a "no" here is trustworthy. Everything derived from text caps at amber.
    static func evaluateStructured(_ eligibility: EligibilityModule?, profile: Profile) -> [StructuredCheck] {
        guard let eligibility else { return [] }
        var checks: [StructuredCheck] = []

        // Age
        if let age = profile.age {
            let minYears = AgeBound(eligibility.minimumAge)?.years
            let maxYears = AgeBound(eligibility.maximumAge)?.years
            if minYears != nil || maxYears != nil {
                let range = [minYears.map { "\(fmt($0))+" }, maxYears.map { "up to \(fmt($0))" }]
                    .compactMap { $0 }.joined(separator: ", ")
                let tooYoung = minYears.map { Double(age) < $0 } ?? false
                let tooOld = maxYears.map { Double(age) > $0 } ?? false
                checks.append(StructuredCheck(
                    label: "Age",
                    verdict: (tooYoung || tooOld) ? .blocker : .match,
                    rationale: (tooYoung || tooOld)
                        ? "You entered \(age); this trial accepts \(range)"
                        : "You entered \(age); this trial accepts \(range)"))
            }
        }

        // Sex
        if let trialSex = eligibility.sex?.uppercased(), trialSex != "ALL", let profileSex = profile.sex {
            let wanted = trialSex.lowercased()
            let mismatch = wanted != profileSex.rawValue
            checks.append(StructuredCheck(
                label: "Sex",
                verdict: mismatch ? .blocker : .match,
                rationale: mismatch
                    ? "This trial enrols \(wanted) participants only"
                    : "This trial enrols \(wanted) participants"))
        }

        return checks
    }

    static func evaluate(_ criteria: [Criterion], profile: Profile) -> [EvaluatedCriterion] {
        criteria.map { criterion in
            let category = Categorizer.categorize(criterion.text, profile: profile)
            let (verdict, rationale) = judge(criterion, category: category, profile: profile)
            return EvaluatedCriterion(criterion: criterion, category: category,
                                      verdict: verdict, rationale: rationale)
        }
    }

    // MARK: - Per-category judgement

    private static func judge(_ criterion: Criterion, category: Category, profile: Profile)
        -> (Verdict, String)
    {
        let text = criterion.text.lowercased()

        switch category {
        case .bmi:
            guard let bmi = profile.bmi else { return (.ask, "We don't have your height and weight") }
            guard let range = NumericRange.extract(from: text) else {
                return (.ask, "Your BMI is \(fmt(bmi)) — check the exact range with the study team")
            }
            let inside = range.contains(bmi)
            // Outside the range still caps at amber: weight changes, and the
            // range may apply only to one treatment group.
            return (inside ? .match : .ask,
                    inside ? "Your BMI is about \(fmt(bmi))"
                           : "Your BMI is about \(fmt(bmi)); this asks for \(range.description)")

        case .age:
            guard let age = profile.age else { return (.ask, "We don't have your age") }
            guard let range = NumericRange.extract(from: text) else {
                return (.ask, "You're \(age) — confirm the age range with the study team")
            }
            return range.contains(Double(age))
                ? (.match, "You entered \(age)")
                : (.ask, "You're \(age); this mentions \(range.description)")

        case .sex:
            guard let sex = profile.sex else { return (.ask, "We don't have your sex") }
            let mentionsFemale = text.contains("female") || text.contains("women") || text.contains("woman")
            let mentionsMale = text.range(of: #"\bmale\b|\bmales\b|\bmen\b|\bman\b"#,
                                          options: .regularExpression) != nil
            if mentionsFemale && mentionsMale { return (.match, "Open to all sexes") }
            if mentionsFemale && sex == .female { return (.match, "You entered female") }
            if mentionsMale && sex == .male { return (.match, "You entered male") }
            return (.ask, "Check this one with the study team")

        case .diagnosis:
            if let hit = profile.allTerms.first(where: { text.contains($0) }) {
                return (.match, "You entered “\(hit)”")
            }
            return (.ask, "Confirm this matches your diagnosis")

        case .priorTherapy:
            // A hit here is important but never a firm no — free-text medication
            // entry is too unreliable to disqualify someone on.
            if let hit = profile.allTerms.first(where: { text.contains($0) }) {
                return (.ask, "You listed “\(hit)” — ask specifically about this")
            }
            return (.ask, "Ask about your treatment history")

        case .labValue:
            return (.ask, "Needs recent bloodwork")

        case .performanceStatus:
            return (.ask, "Your care team can score this")

        case .pregnancy:
            return (.ask, "Ask the study team")

        case .consent:
            // Not a medical hurdle — it's paperwork everyone signs.
            return (.match, "Standard for all trials")

        case .other:
            return (.ask, "Bring this one to your care team")
        }
    }

    private static func fmt(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
    }
}

// MARK: - Pulling numbers out of prose

/// Finds things like "between 35 and 50", "18 to 60", "≥ 18", "at most 85".
struct NumericRange {
    let min: Double?
    let max: Double?

    func contains(_ value: Double) -> Bool {
        if let min, value < min { return false }
        if let max, value > max { return false }
        return true
    }

    var description: String {
        switch (min, max) {
        case let (m?, x?): return "\(fmt(m))–\(fmt(x))"
        case let (m?, nil): return "\(fmt(m)) or above"
        case let (nil, x?): return "\(fmt(x)) or below"
        default: return "an unspecified range"
        }
    }

    private func fmt(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
    }

    static func extract(from text: String) -> NumericRange? {
        // Two-ended: "between 35 and 50", "18 to 60", "18-60"
        let twoEnded = [
            #"between\s+(\d+(?:\.\d+)?)\s*(?:and|to|-|–)\s*(\d+(?:\.\d+)?)"#,
            #"(\d+(?:\.\d+)?)\s*(?:to|-|–)\s*(\d+(?:\.\d+)?)\s*(?:years|kg/m|$|\s)"#,
        ]
        for pattern in twoEnded {
            if let m = firstMatch(pattern, in: text), m.count >= 3,
               let lo = Double(m[1]), let hi = Double(m[2]) {
                return NumericRange(min: Swift.min(lo, hi), max: Swift.max(lo, hi))
            }
        }

        // One-ended lower bound: "≥ 18", ">= 18", "at least 18", "18 years or older"
        let lower = [
            #"(?:≥|>=|at least|greater than or equal to|minimum of)\s*(\d+(?:\.\d+)?)"#,
            #"(\d+(?:\.\d+)?)\s*(?:years|yrs)?\s*(?:of age)?\s*(?:or older|and older|or above)"#,
        ]
        // One-ended upper bound: "≤ 85", "at most 85", "no more than 85"
        let upper = [
            #"(?:≤|<=|at most|no more than|not exceed(?:ing)?|maximum of)\s*(\d+(?:\.\d+)?)"#,
            #"(\d+(?:\.\d+)?)\s*(?:years|yrs)?\s*(?:of age)?\s*(?:or younger|or below)"#,
        ]

        var minValue: Double? = nil
        var maxValue: Double? = nil
        for pattern in lower {
            if let m = firstMatch(pattern, in: text), m.count >= 2 { minValue = Double(m[1]); break }
        }
        for pattern in upper {
            if let m = firstMatch(pattern, in: text), m.count >= 2 { maxValue = Double(m[1]); break }
        }

        guard minValue != nil || maxValue != nil else { return nil }
        return NumericRange(min: minValue, max: maxValue)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
