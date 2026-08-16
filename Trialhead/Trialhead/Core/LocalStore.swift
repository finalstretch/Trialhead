import Foundation

/// Everything the app remembers between launches.
struct StoredState: Codable, Equatable {
    var profile = Profile()
    var settings = SearchSettings()
    var savedTrialIDs: [String] = []
    var hasSeenWelcome = false
    var hasCompletedTour = false
    var hasCompletedOnboarding = false
}

/// Forgiving decoding, same reasoning as `Profile` — a missing top-level key
/// must not discard the keys that *are* there.
extension StoredState {
    enum CodingKeys: String, CodingKey {
        case profile, settings, savedTrialIDs, hasSeenWelcome, hasCompletedTour, hasCompletedOnboarding
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        profile = try container.decodeIfPresent(Profile.self, forKey: .profile) ?? Profile()
        settings = try container.decodeIfPresent(SearchSettings.self, forKey: .settings) ?? SearchSettings()
        savedTrialIDs = try container.decodeIfPresent([String].self, forKey: .savedTrialIDs) ?? []
        hasSeenWelcome = try container.decodeIfPresent(Bool.self, forKey: .hasSeenWelcome) ?? false
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        hasCompletedTour = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedTour) ?? false
    }
}

/// Saves to a single JSON file inside the app's own private folder.
///
/// DESIGN.md Principle 3 — health data never leaves the device. A plain file in
/// the app sandbox satisfies that: no account, no server, no sync. It also makes
/// "delete everything" honest, since there is exactly one file to remove.
enum LocalStore {

    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("trialhead-state.json")
    }

    static func load() -> StoredState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(StoredState.self, from: data)
        else { return StoredState() }
        return state
    }

    static func save(_ state: StoredState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        // .atomic writes to a temp file first, so a crash mid-write can't leave
        // a half-written file that fails to load next launch.
        try? data.write(to: fileURL, options: .atomic)
    }

    static func deleteEverything() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Shown on the privacy screen so the claim is checkable, not just asserted.
    static var fileDescription: String {
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        return exists ? "Stored in one file on this device" : "Nothing stored yet"
    }
}
