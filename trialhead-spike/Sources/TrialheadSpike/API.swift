import Foundation

/// Minimal ClinicalTrials.gov API v2 client.
/// Verified live against the API on 2026-08-14 — see NOTES.md for what held up.
struct TrialsAPI {
    private let base = URL(string: "https://clinicaltrials.gov/api/v2")!

    /// Field paths worth requesting. Full records are large; `fields` trims them.
    static let defaultFields = [
        "protocolSection.identificationModule.nctId",
        "protocolSection.identificationModule.briefTitle",
        "protocolSection.statusModule.overallStatus",
        "protocolSection.descriptionModule.briefSummary",
        "protocolSection.conditionsModule.conditions",
        "protocolSection.designModule.studyType",
        "protocolSection.designModule.phases",
        "protocolSection.designModule.enrollmentInfo",
        "protocolSection.eligibilityModule",
        "protocolSection.contactsLocationsModule.locations",
        "protocolSection.contactsLocationsModule.centralContacts",
        "protocolSection.sponsorCollaboratorsModule.leadSponsor",
    ]

    struct SearchQuery {
        var condition: String
        var status: [String] = ["RECRUITING"]
        var studyType: String? = nil            // e.g. "INTERVENTIONAL"
        var geo: (lat: Double, lon: Double, radiusMiles: Int)? = nil
        var pageSize: Int = 20
        var pageToken: String? = nil
        var fields: [String] = defaultFields
    }

    func search(_ q: SearchQuery) async throws -> StudiesResponse {
        var items: [URLQueryItem] = [
            .init(name: "query.cond", value: q.condition),
            .init(name: "pageSize", value: String(q.pageSize)),
            .init(name: "countTotal", value: "true"),
            .init(name: "fields", value: q.fields.joined(separator: ",")),
        ]
        if !q.status.isEmpty {
            items.append(.init(name: "filter.overallStatus", value: q.status.joined(separator: "|")))
        }
        if let type = q.studyType {
            // studyType has no dedicated filter param; advanced filter syntax handles it.
            items.append(.init(name: "filter.advanced", value: "AREA[StudyType]\(type)"))
        }
        if let geo = q.geo {
            items.append(.init(name: "filter.geo",
                               value: "distance(\(geo.lat),\(geo.lon),\(geo.radiusMiles)mi)"))
        }
        if let token = q.pageToken {
            items.append(.init(name: "pageToken", value: token))
        }

        var comps = URLComponents(url: base.appendingPathComponent("studies"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = items
        return try await get(comps.url!, as: StudiesResponse.self)
    }

    func study(nctId: String) async throws -> Study {
        let url = base.appendingPathComponent("studies").appendingPathComponent(nctId)
        return try await get(url, as: Study.self)
    }

    /// Raw bytes, for dumping samples the parser spike (M1) will chew on.
    func raw(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        try check(response, url: url)
        return data
    }

    private func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        try check(response, url: url)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SpikeError.decoding(url: url, underlying: error)
        }
    }

    private func check(_ response: URLResponse, url: URL) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw SpikeError.http(status: http.statusCode, url: url)
        }
    }
}

enum SpikeError: Error, CustomStringConvertible {
    case http(status: Int, url: URL)
    case decoding(url: URL, underlying: Error)
    case usage(String)

    var description: String {
        switch self {
        case let .http(status, url):
            return "HTTP \(status) from \(url.absoluteString)"
        case let .decoding(url, underlying):
            return "Failed to decode \(url.absoluteString)\n  \(underlying)"
        case let .usage(message):
            return message
        }
    }
}
