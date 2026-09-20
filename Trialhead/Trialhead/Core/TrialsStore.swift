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
    var hasSeenWelcome: Bool { didSet { persist() } }
    var hasCompletedOnboarding: Bool { didSet { persist() } }
    var hasCompletedTour: Bool { didSet { persist() } }
    var textSize: TextSize { didSet { persist() } }

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
        var loaded = stored.settings
        loaded.clampRadius()   // files saved before the 30-mile cap existed
        settings = loaded
        savedTrialIDs = Set(stored.savedTrialIDs)
        hasSeenWelcome = stored.hasSeenWelcome
        hasCompletedOnboarding = stored.hasCompletedOnboarding
        hasCompletedTour = stored.hasCompletedTour
        textSize = stored.textSize
    }

    // MARK: - Where to search

    var isResolvingLocation = false
    var locationError: String?

    /// Turns the typed ZIP or city into coordinates, then re-runs the search.
    @MainActor
    func applyLocation(query: String, mode: LocationMode, radius: Int) async {
        isResolvingLocation = true
        locationError = nil
        defer { isResolvingLocation = false }

        do {
            let place = try await LocationResolver.resolve(query, mode: mode)
            settings.locationMode = mode
            settings.locationQuery = query
            settings.locationLabel = place.label
            settings.latitude = place.latitude
            settings.longitude = place.longitude
            settings.radiusMiles = radius
            await search()
        } catch {
            locationError = FriendlyError.message(for: error)
        }
    }

    private func persist() {
        LocalStore.save(StoredState(profile: profile,
                                    settings: settings,
                                    savedTrialIDs: Array(savedTrialIDs).sorted(),
                                    hasSeenWelcome: hasSeenWelcome,
                                    hasCompletedTour: hasCompletedTour,
                                    hasCompletedOnboarding: hasCompletedOnboarding,
                                    textSize: textSize))
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
        // Back to a genuinely blank slate — including the introduction.
        hasSeenWelcome = false
        hasCompletedTour = false
        hasCompletedOnboarding = false
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
        summaries
            .filter { !hideIneligible || !$0.categoricallyIneligible }
            .filter { matchesPhaseFilter($0) }
    }

    /// Empty selection means no filter — show everything.
    private func matchesPhaseFilter(_ summary: TrialSummary) -> Bool {
        guard !settings.selectedPhases.isEmpty else { return true }
        return !Set(summary.phaseKeys).isDisjoint(with: settings.selectedPhases)
    }

    var hiddenCount: Int {
        summaries.filter(\.categoricallyIneligible).count
    }

    /// How many trials each phase would show, so the checkboxes can display
    /// counts and someone can see a filter is empty before they apply it.
    func phaseCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for summary in summaries where !hideIneligible || !summary.categoricallyIneligible {
            for key in summary.phaseKeys { counts[key, default: 0] += 1 }
        }
        return counts
    }

    func togglePhase(_ phase: TrialPhase) {
        if settings.selectedPhases.contains(phase.rawValue) {
            settings.selectedPhases.remove(phase.rawValue)
        } else {
            settings.selectedPhases.insert(phase.rawValue)
        }
    }

    func clearPhaseFilter() { settings.selectedPhases = [] }

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
            errorMessage = FriendlyError.message(for: error)
        }
    }

    func study(_ nctId: String) -> Study? { studiesById[nctId] }
}
