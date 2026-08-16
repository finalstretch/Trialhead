import SwiftUI

/// DESIGN.md §5.7. A shortlist you can come back to — the trials worth phoning
/// about, kept apart from a search that changes every time you use it.
struct SavedView: View {
    @Bindable var store: TrialsStore
    @Binding var path: [String]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.savedTrialIDs.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing saved yet", systemImage: "bookmark")
                    } description: {
                        Text("Tap the bookmark on a trial to keep it here — a shortlist of the ones worth calling about.")
                    }
                } else if store.isLoadingSaved && store.savedSummaries.isEmpty {
                    ProgressView("Loading saved trials…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
            .navigationTitle("Saved")
            .task { await store.loadSaved() }
            .refreshable { await store.loadSaved() }
        }
    }

    private var list: some View {
        List {
            ForEach(store.savedSummaries) { summary in
                NavigationLink(value: summary.nctId) {
                    TrialCard(summary: summary)
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    store.toggleSaved(store.savedSummaries[index].nctId)
                }
                Task { await store.loadSaved() }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: String.self) { nctId in
            if let study = store.study(nctId) {
                TrialDetailView(study: study, store: store)
            }
        }
    }
}
