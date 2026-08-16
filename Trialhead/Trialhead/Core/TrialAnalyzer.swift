import Foundation
import CoreLocation

/// Where the person is searching from. Kept separate from `Profile` on purpose:
/// this is a search setting, not a health fact.
struct SearchSettings: Codable, Equatable {
    var condition: String = "breast cancer"

    // Where to search from — entered as a ZIP code or a city, then resolved to
    // coordinates by LocationResolver.
    var locationMode: LocationMode = .city
    var locationQuery: String = "New York, NY"
    var locationLabel: String = "New York, NY"
    var latitude: Double = 40.7128
    var longitude: Double = -74.0060

    /// Travel radius in miles. Capped deliberately — see `maxRadiusMiles`.
    var radiusMiles: Int = 25 {
        didSet { radiusMiles = min(max(radiusMiles, Self.minRadiusMiles), Self.maxRadiusMiles) }
    }

    /// Trials commonly need weekly in-person visits, so anything beyond a short
    /// drive stops being realistic. Capping the search at 30 miles keeps results
    /// honest rather than padding the list with places nobody would travel to.
    static let maxRadiusMiles = 30
    static let minRadiusMiles = 5

    /// Computed, so it isn't stored — `Codable` only saves the numbers.
    var coordinate: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    /// Older saved files may hold a radius from before the cap existed.
    mutating func clampRadius() {
        radiusMiles = min(max(radiusMiles, Self.minRadiusMiles), Self.maxRadiusMiles)
    }
}

/// Same forgiving decoding as `Profile` — see the note there. This type has
/// gained fields twice already, and each time the automatic version would have
/// wiped every saved file.
extension SearchSettings {
    enum CodingKeys: String, CodingKey {
        case condition, locationMode, locationQuery, locationLabel
        case latitude, longitude, radiusMiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        condition = try container.decodeIfPresent(String.self, forKey: .condition) ?? condition
        locationMode = try container.decodeIfPresent(LocationMode.self, forKey: .locationMode) ?? locationMode
        locationQuery = try container.decodeIfPresent(String.self, forKey: .locationQuery) ?? locationQuery
        locationLabel = try container.decodeIfPresent(String.self, forKey: .locationLabel) ?? locationLabel
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude) ?? latitude
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude) ?? longitude
        radiusMiles = try container.decodeIfPresent(Int.self, forKey: .radiusMiles) ?? radiusMiles
        clampRadius()   // `didSet` doesn't fire during initialisation
    }
}

/// Everything one row of the results list needs.
/// Per DESIGN.md §5.2 (revised after M2): distance and a question count —
/// deliberately NOT a fit score.
struct TrialSummary: Identifiable {
    let nctId: String
    let title: String
    let status: String
    let phase: String?
    let sponsor: String?
    let siteCount: Int
    let nearestSite: Location?
    let distanceMiles: Double?
    let questionCount: Int
    let looksFineCount: Int
    /// Age or sex rules out this person — from exact fields in the trial
    /// record, so trustworthy enough to act on.
    let categoricallyIneligible: Bool

    var id: String { nctId }
}

/// Turns a raw study into something the screens can show.
enum TrialAnalyzer {

    static func summarize(_ study: Study, profile: Profile, from settings: SearchSettings) -> TrialSummary? {
        guard let section = study.protocolSection,
              let nctId = section.identificationModule?.nctId else { return nil }

        let sites = section.contactsLocationsModule?.locations ?? []
        let nearest = nearestSite(among: sites, to: settings.coordinate)

        let evaluation = evaluate(study, profile: profile)
        let structuredBlocked = evaluation.structured.contains { $0.verdict == .blocker }

        return TrialSummary(
            nctId: nctId,
            title: section.identificationModule?.briefTitle ?? "Untitled study",
            status: section.statusModule?.overallStatus ?? "UNKNOWN",
            phase: section.designModule?.phases?.first,
            sponsor: section.sponsorCollaboratorsModule?.leadSponsor?.name,
            siteCount: sites.count,
            nearestSite: nearest?.site,
            distanceMiles: nearest?.miles,
            questionCount: evaluation.asks,
            looksFineCount: evaluation.matches,
            categoricallyIneligible: structuredBlocked)
    }

    /// Full pipeline: split the criteria, categorise them, assign verdicts.
    static func evaluate(_ study: Study, profile: Profile) -> TrialEvaluation {
        let eligibility = study.protocolSection?.eligibilityModule
        let parsed = CriteriaParser.parse(eligibility?.eligibilityCriteria ?? "")
        return TrialEvaluation(
            structured: Evaluator.evaluateStructured(eligibility, profile: profile),
            criteria: Evaluator.evaluate(parsed.criteria, profile: profile))
    }

    /// True when the criteria text couldn't be broken into a checklist at all.
    /// DESIGN.md §11.8 — these fall back to showing the original text.
    static func parseFailed(_ study: Study) -> Bool {
        let text = study.protocolSection?.eligibilityModule?.eligibilityCriteria ?? ""
        guard !text.isEmpty else { return true }
        let parsed = CriteriaParser.parse(text)
        return parsed.criteria.count < 2
            || (!parsed.foundInclusionHeader && !parsed.foundExclusionHeader)
    }

    static func nearestSite(among sites: [Location], to origin: CLLocation)
        -> (site: Location, miles: Double)?
    {
        sites
            .compactMap { site -> (Location, Double)? in
                guard let point = site.geoPoint else { return nil }
                let metres = origin.distance(from: CLLocation(latitude: point.lat, longitude: point.lon))
                return (site, metres / 1609.344)
            }
            .min { $0.1 < $1.1 }
            .map { (site: $0.0, miles: $0.1) }
    }
}
