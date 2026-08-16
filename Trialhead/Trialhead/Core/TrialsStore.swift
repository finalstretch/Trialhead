import Foundation
import Observation

/// Holds the app's data and does the fetching.
/// `@Observable` means SwiftUI redraws automatically whenever these change.
@Observable
final class TrialsStore {
    var profile = Profile.breastCancerExample
    var settings = SearchSettings()

    var summaries: [TrialSummary] = []
    var studiesById: [String: Study] = [:]

    var isLoading = false
    var errorMessage: String?

    /// Hide trials the person is categorically ineligible for (age or sex).
    var hideIneligible = true

    private let api = TrialsAPI()

    var visibleSummaries: [TrialSummary] {
        hideIneligible ? summaries.filter { !$0.categoricallyIneligible } : summaries
    }

    var hiddenCount: Int {
        summaries.filter(\.categoricallyIneligible).count
    }

    @MainActor
    func search() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var query = TrialsAPI.SearchQuery(condition: settings.condition)
        query.studyType = "INTERVENTIONAL"
        query.geo = (settings.latitude, settings.longitude, settings.radiusMiles)
        query.pageSize = 25

        do {
            let response = try await api.search(query)
            var built: [TrialSummary] = []
            var byId: [String: Study] = [:]

            for study in response.studies {
                guard let summary = TrialAnalyzer.summarize(study, profile: profile, from: settings)
                else { continue }
                built.append(summary)
                byId[summary.nctId] = study
            }

            // Nearest first — distance is the strongest real differentiator.
            summaries = built.sorted { ($0.distanceMiles ?? .infinity) < ($1.distanceMiles ?? .infinity) }
            studiesById = byId
        } catch {
            errorMessage = "\(error)"
        }
    }

    func study(_ nctId: String) -> Study? { studiesById[nctId] }
}
