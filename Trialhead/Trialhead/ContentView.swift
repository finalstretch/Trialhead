import SwiftUI

struct ContentView: View {
    @State private var store = TrialsStore()
    @State private var tour = Tour()
    @State private var selectedTab = Tab.trials
    @State private var matchesPath: [String] = []
    @State private var savedPath: [String] = []

    enum Tab { case trials, saved, profile }

    var body: some View {
        TabView(selection: tabSelection) {
            MatchesView(store: store, path: $matchesPath)
                .tabItem { Label("Trials", systemImage: "list.bullet") }
                .tag(Tab.trials)

            SavedView(store: store, path: $savedPath)
                .tabItem { Label("Saved", systemImage: "bookmark") }
                .badge(store.savedTrialIDs.count)
                .tag(Tab.saved)

            ProfileView(store: store)
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(Tab.profile)
        }
        .environment(tour)
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            // `ignoresSafeArea` belongs on the GeometryReader, not inside the
            // overlay. Applied inside, it expands the drawing area *after* the
            // frames were measured, so every spotlight lands one status-bar
            // height too high.
            GeometryReader { proxy in
                TourOverlay(store: store, tour: tour, anchors: anchors, proxy: proxy)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: .constant(firstRun != nil)) {
            if let firstRun {
                OnboardingView(store: store, mode: firstRun)
            }
        }
        // The walkthrough starts once the welcome screen is dismissed, and
        // setup follows when it ends.
        .onChange(of: store.hasSeenWelcome) { _, seen in
            if seen && !store.hasCompletedTour { tour.start() }
        }
        // Also covers the app being killed part-way through the walkthrough —
        // it restarts rather than silently never appearing again.
        .onAppear {
            if store.hasSeenWelcome && !store.hasCompletedTour && !tour.isRunning {
                tour.start()
            }
        }
        .onChange(of: tour.step) { _, step in
            syncNavigation(for: step)
        }
    }

    /// First run runs welcome → tour → setup. The tour sits *between* the two
    /// halves of onboarding: someone who has seen how the app works understands
    /// why it's asking for their height, and is far likelier to answer.
    private var firstRun: OnboardingView.Mode? {
        if !store.hasSeenWelcome { return .welcome }
        if store.hasCompletedTour && !store.hasCompletedOnboarding { return .setup }
        return nil
    }

    /// The tour spans several screens, so it drives navigation itself.
    ///
    /// Written as "put the app wherever this step needs it" rather than "handle
    /// moving forward", which is what makes the Back button work: going
    /// backwards is just another step needing its own screen.
    private func syncNavigation(for step: Tour.Step?) {
        guard let step else {
            // Finished or skipped: don't show it again.
            store.hasCompletedTour = true
            matchesPath.removeAll()
            selectedTab = .trials
            return
        }

        if step.isOnDetailScreen {
            selectedTab = .trials
            // Stepping back from the Profile step lands here with no trial open,
            // so re-open the one the tour was using.
            if matchesPath.isEmpty, let first = store.visibleSummaries.first {
                matchesPath = [first.nctId]
            }
            return
        }

        switch step {
        case .profileTab:
            matchesPath.removeAll()
            selectedTab = .profile
        case .savedTab:
            selectedTab = .saved
        default:
            // Every remaining step belongs on the trials list.
            selectedTab = .trials
            matchesPath.removeAll()
        }
    }

    /// Tapping the tab you're already on returns you to the top of that tab.
    /// Standard iOS behaviour, and here it's the main way back out of a trial —
    /// iOS 26 renders the back button as a small unlabelled chevron that people
    /// genuinely miss.
    private var tabSelection: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { tapped in
                if tapped == selectedTab {
                    switch tapped {
                    case .trials: matchesPath.removeAll()
                    case .saved: savedPath.removeAll()
                    case .profile: break
                    }
                }
                selectedTab = tapped
            })
    }
}

#Preview {
    ContentView()
}
