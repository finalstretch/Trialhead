import Foundation
import Observation

/// Holds the app's data and does the fetching.
/// `@Observable` means SwiftUI redraws automatically whenever these change.
@Observable
final class TrialsStore {

    // Anything with `didSet { persist() }` survives closing the app.
    var profile: Profile { didSet { persist() } }
    var settings: SearchSettings { didSet { persist() } }
    var savedTrialIDs: Set<String> { didSet { persist() } }

    var summaries: [TrialSummary] = []
    var savedSummaries: [TrialSummary] = []
    var studiesById: [String: Study] = [:]

    var isLoading = false
    var isLoadingSaved = false
    var errorMessage: String?

    /// Hide trials the person is categorically ineligible for (age or sex).
    var hideIneligible = true

    private let api = TrialsAPI()

    init() {
        let stored = LocalStore.load()
        profile = stored.profile
        settings = stored.settings
        savedTrialIDs = Set(stored.savedTrialIDs)
    }

    private func persist() {
        LocalStore.save(StoredState(profile: profile,
                                    settings: settings,
                                    savedTrialIDs: Array(savedTrialIDs).sorted()))
    }

    /// Wipes stored details and returns the app to a blank slate.
    func deleteEverything() {
        LocalStore.deleteEverything()
        // Assigning triggers `didSet`, which would rewrite the file we just
        // deleted — so write the blank state deliberately afterwards.
        profile = Profile()
        settings = SearchSettings()
        savedTrialIDs = []
        summaries = []
        studiesById = [:]
    }

    // MARK: - Saved trials

    func isSaved(_ nctId: String) -> Bool { savedTrialIDs.contains(nctId) }

    func toggleSaved(_ nctId: String) {
        if savedTrialIDs.contains(nctId) {
            savedTrialIDs.remove(nctId)
        } else {
            savedTrialIDs.insert(nctId)
        }
    }

    /// Saved trials are fetched by ID rather than filtered out of the current
    /// search — otherwise something saved under "breast cancer" would vanish
    /// the moment you searched for something else.
    @MainActor
    func loadSaved() async {
        isLoadingSaved = true
        defer { isLoadingSaved = false }

        var built: [TrialSummary] = []
        for nctId in savedTrialIDs.sorted() {
            var study = studiesById[nctId]
            if study == nil { study = try? await api.study(nctId: nctId) }
            guard let study else { continue }
            studiesById[nctId] = study
            if let summary = TrialAnalyzer.summarize(study, profile: profile, from: settings) {
                built.append(summary)
            }
        }
        savedSummaries = built
    }

    // MARK: - Search

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

            // Nearest first — distance is coarse (city-level), but it still
            // separates "in your city" from "three hours away".
            summaries = built.sorted { ($0.distanceMiles ?? .infinity) < ($1.distanceMiles ?? .infinity) }
            studiesById = byId
        } catch {
            errorMessage = "\(error)"
        }
    }

    func study(_ nctId: String) -> Study? { studiesById[nctId] }
}
