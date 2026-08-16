import SwiftUI

struct ContentView: View {
    @State private var store = TrialsStore()
    @State private var selectedTab = Tab.trials
    @State private var matchesPath: [String] = []

    enum Tab { case trials, profile }

    var body: some View {
        TabView(selection: tabSelection) {
            MatchesView(store: store, path: $matchesPath)
                .tabItem { Label("Trials", systemImage: "list.bullet") }
                .tag(Tab.trials)

            ProfileView(store: store)
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(Tab.profile)
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
                if tapped == selectedTab, tapped == .trials {
                    matchesPath.removeAll()
                }
                selectedTab = tapped
            })
    }
}

#Preview {
    ContentView()
}
