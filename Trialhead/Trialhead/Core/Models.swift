import Foundation

// Codable mirror of the subset of ClinicalTrials.gov API v2 we actually use.
// Every field is optional: the API omits whole modules depending on study type.
// (An OBSERVATIONAL study, for example, carries no `phases`.)

struct StudiesResponse: Decodable {
    let totalCount: Int?
    let studies: [Study]
    let nextPageToken: String?
}

struct Study: Decodable {
    let protocolSection: ProtocolSection?
}

struct ProtocolSection: Decodable {
    let identificationModule: IdentificationModule?
    let statusModule: StatusModule?
    let descriptionModule: DescriptionModule?
    let conditionsModule: ConditionsModule?
    let designModule: DesignModule?
    let eligibilityModule: EligibilityModule?
    let contactsLocationsModule: ContactsLocationsModule?
    let sponsorCollaboratorsModule: SponsorCollaboratorsModule?
}

struct IdentificationModule: Decodable {
    let nctId: String?
    let briefTitle: String?
    let officialTitle: String?
}

struct StatusModule: Decodable {
    let overallStatus: String?
    let lastUpdatePostDateStruct: DateStruct?

    struct DateStruct: Decodable { let date: String? }
}

struct DescriptionModule: Decodable {
    let briefSummary: String?
    let detailedDescription: String?
}

struct ConditionsModule: Decodable {
    let conditions: [String]?
    let keywords: [String]?
}

struct DesignModule: Decodable {
    let studyType: String?          // INTERVENTIONAL | OBSERVATIONAL | EXPANDED_ACCESS
    let phases: [String]?           // absent on observational studies
    let enrollmentInfo: EnrollmentInfo?

    struct EnrollmentInfo: Decodable {
        let count: Int?
        let type: String?           // ESTIMATED | ACTUAL
    }
}

struct SponsorCollaboratorsModule: Decodable {
    let leadSponsor: Sponsor?
    struct Sponsor: Decodable {
        let name: String?
        let `class`: String?
    }
}

struct ContactsLocationsModule: Decodable {
    let centralContacts: [Contact]?
    let locations: [Location]?
}

struct Contact: Decodable {
    let name: String?
    let role: String?               // CONTACT | PRINCIPAL_INVESTIGATOR | ...
    let phone: String?
    let email: String?
}

struct Location: Decodable {
    let facility: String?
    let status: String?             // per-site status; may differ from overall
    let city: String?
    let state: String?
    let zip: String?
    let country: String?
    let contacts: [Contact]?
    let geoPoint: GeoPoint?

    struct GeoPoint: Decodable {
        let lat: Double
        let lon: Double
    }
}

// MARK: - Eligibility

struct EligibilityModule: Decodable {
    let eligibilityCriteria: String?   // the unstructured blob — the whole problem
    let healthyVolunteers: Bool?
    let sex: String?                   // ALL | FEMALE | MALE
    let minimumAge: String?            // "18 Years", "6 Months", sometimes absent
    let maximumAge: String?
    let stdAges: [String]?             // CHILD | ADULT | OLDER_ADULT
}

/// The API returns ages as human strings ("18 Years", "6 Months"), not numbers.
/// DESIGN.md §8 models these as `Int?` — that is wrong and needs updating.
struct AgeBound {
    let value: Double
    let unit: Unit

    enum Unit: String {
        case years = "Years", months = "Months", weeks = "Weeks", days = "Days"

        var inYears: Double {
            switch self {
            case .years:  return 1
            case .months: return 1.0 / 12
            case .weeks:  return 1.0 / 52.1775
            case .days:   return 1.0 / 365.25
            }
        }
    }

    var years: Double { value * unit.inYears }

    init?(_ raw: String?) {
        guard let raw else { return nil }
        let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard parts.count == 2,
              let value = Double(parts[0]),
              let unit = Unit(rawValue: String(parts[1]))
        else { return nil }
        self.value = value
        self.unit = unit
    }
}
