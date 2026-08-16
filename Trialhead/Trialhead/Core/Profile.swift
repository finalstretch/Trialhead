import Foundation

/// Everything the app knows about the person using it.
/// In the real app this is filled in during setup and stored only on the phone.
struct Profile: Codable, Equatable {
    enum Sex: String, Codable { case female, male }

    var age: Int?
    var sex: Sex?
    var conditions: [String] = []        // "type 2 diabetes"
    var priorTreatments: [String] = []   // surgeries, chemo, past drugs
    var medications: [String] = []       // what they take now
    var heightCM: Double?
    var weightKG: Double?

    /// Body Mass Index — a single number combining height and weight.
    /// Trials use it constantly, and it costs the user only two questions.
    var bmi: Double? {
        guard let heightCM, let weightKG, heightCM > 0 else { return nil }
        let metres = heightCM / 100
        return weightKG / (metres * metres)
    }

    /// What the person said is wrong with them.
    var conditionTerms: [String] { Profile.normalize(conditions) }

    /// What the person said they've been treated with.
    var treatmentTerms: [String] { Profile.normalize(priorTreatments + medications) }

    var allTerms: [String] { conditionTerms + treatmentTerms }

    private static func normalize(_ values: [String]) -> [String] {
        values
            .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 }   // "ra" would match far too much text
    }
}

// MARK: - Forgiving decoding

/// Swift's automatic decoding demands that *every* field be present, so adding
/// one new property makes every previously-saved file fail to decode — and the
/// person's whole profile silently disappears on the next launch.
///
/// Decoding each field with `decodeIfPresent` and falling back to the default
/// means old files keep loading as new fields are added. Written in an extension
/// so the memberwise `Profile(age:sex:…)` initialiser survives.
extension Profile {
    enum CodingKeys: String, CodingKey {
        case age, sex, conditions, priorTreatments, medications, heightCM, weightKG
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        age = try container.decodeIfPresent(Int.self, forKey: .age)
        sex = try container.decodeIfPresent(Sex.self, forKey: .sex)
        conditions = try container.decodeIfPresent([String].self, forKey: .conditions) ?? []
        priorTreatments = try container.decodeIfPresent([String].self, forKey: .priorTreatments) ?? []
        medications = try container.decodeIfPresent([String].self, forKey: .medications) ?? []
        heightCM = try container.decodeIfPresent(Double.self, forKey: .heightCM)
        weightKG = try container.decodeIfPresent(Double.self, forKey: .weightKG)
    }
}

extension Profile {
    /// Stand-in profiles for testing. The real app builds these from onboarding.
    static let diabetesExample = Profile(
        age: 45,
        sex: .female,
        conditions: ["type 2 diabetes"],
        priorTreatments: [],
        medications: ["metformin"],
        heightCM: 165,
        weightKG: 104        // BMI ≈ 38
    )

    static let breastCancerExample = Profile(
        age: 62,
        sex: .female,
        conditions: ["breast cancer"],
        priorTreatments: ["mastectomy", "docetaxel"],
        medications: ["pembrolizumab"],
        heightCM: 160,
        weightKG: 68
    )
}
