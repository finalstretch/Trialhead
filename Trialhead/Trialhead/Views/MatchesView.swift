import SwiftUI

struct MatchesView: View {
    @Bindable var store: TrialsStore
    /// Owned by ContentView so tapping the Trials tab can pop back to the list.
    @Binding var path: [String]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.isLoading && store.summaries.isEmpty {
                    ProgressView("Finding trials…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = store.errorMessage {
                    ErrorState(message: error) { Task { await store.search() } }
                } else if store.summaries.isEmpty {
                    EmptyState()
                } else {
                    list
                }
            }
            .navigationTitle("Trials")
            .searchable(text: $store.settings.condition, prompt: "Condition")
            .onSubmit(of: .search) { Task { await store.search() } }
            .task { if store.summaries.isEmpty { await store.search() } }
            .refreshable { await store.search() }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(store.visibleSummaries) { summary in
                    NavigationLink(value: summary.nctId) {
                        TrialCard(summary: summary)
                    }
                }
            } header: {
                Text("\(store.visibleSummaries.count) trials within \(store.settings.radiusMiles) miles")
            } footer: {
                if store.hiddenCount > 0 {
                    Text("\(store.hiddenCount) hidden — the trial record's age or sex requirements rule you out.")
                }
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

// MARK: - Card

/// One row of results. Revised after M2: distance and a question count,
/// deliberately not a fit score — every trial scored about the same.
struct TrialCard: View {
    let summary: TrialSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                StatusPill(status: summary.status)
                if let phase = summary.phase {
                    Text(phase.replacingOccurrences(of: "PHASE", with: "Phase "))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(summary.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let sponsor = summary.sponsor {
                Text(sponsor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 4) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption2)
                Text(distanceText)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            Text("^[\(summary.questionCount) question](inflect: true) to ask")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
        }
        .padding(.vertical, 4)
    }

    /// ClinicalTrials.gov geocodes sites to the CITY CENTRE, not the street
    /// address — every "New York" site shares one coordinate. So sub-city
    /// precision would be invented. Lead with the place name and only show a
    /// mileage once it's far enough to be a real travel decision.
    private var distanceText: String {
        let suffix = summary.siteCount > 1 ? " · nearest of \(summary.siteCount) sites" : ""
        guard let miles = summary.distanceMiles else {
            return "\(summary.siteCount) site\(summary.siteCount == 1 ? "" : "s"), location unlisted"
        }
        let place = [summary.nearestSite?.city, summary.nearestSite?.state]
            .compactMap { $0 }.first ?? "Study site"
        return miles < 20 ? "\(place)\(suffix)" : "\(place) · \(Int(miles.rounded())) mi\(suffix)"
    }
}

struct StatusPill: View {
    let status: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        status.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var color: Color {
        switch status {
        case "RECRUITING": return .green
        case "NOT_YET_RECRUITING", "ENROLLING_BY_INVITATION": return .blue
        default: return .secondary
        }
    }
}

// MARK: - Placeholder states

private struct EmptyState: View {
    var body: some View {
        ContentUnavailableView(
            "No trials found",
            systemImage: "magnifyingglass",
            description: Text("Try a different condition, or widen your search distance in Profile."))
    }
}

private struct ErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't load trials", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message).font(.caption)
        } actions: {
            Button("Try again", action: retry).buttonStyle(.borderedProminent)
        }
    }
}
