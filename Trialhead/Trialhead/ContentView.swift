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
        // An invisible strip over the tab bar, so the tour can highlight it
        // without needing each tab item's exact frame. Sized generously and
        // extended into the bottom safe area so the whole bar — Saved and
        // Profile included — sits inside the spotlight rather than half of it
        // being blurred out.
        .overlay(alignment: .bottom) {
            Color.clear
                .frame(height: 120)
                .allowsHitTesting(false)
                .tourAnchor(.tabBar)
                .ignoresSafeArea(edges: .bottom)
        }
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
        .onChange(of: tour.step) { previous, step in
            handleTourStep(from: previous, to: step)
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

    /// The tour spans two screens, so it has to drive navigation itself.
    private func handleTourStep(from previous: Tour.Step?, to step: Tour.Step?) {
        switch step {
        case .profileTab:
            // Coming off the trial page — go back to the list to talk about tabs.
            matchesPath.removeAll()
            selectedTab = .trials
        case nil:
            // Finished or skipped: don't show it again.
            store.hasCompletedTour = true
            matchesPath.removeAll()
            selectedTab = .trials
        default:
            break
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
