import SwiftUI

struct ContentView: View {
    @State private var store = TrialsStore()
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
        .fullScreenCover(isPresented: .constant(!store.hasCompletedOnboarding)) {
            OnboardingView(store: store)
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
