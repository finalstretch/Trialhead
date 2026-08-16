import SwiftUI

struct MatchesView: View {
    @Bindable var store: TrialsStore
    /// Owned by ContentView so tapping the Trials tab can pop back to the list.
    @Binding var path: [String]
    @State private var showingLocation = false

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingLocation = true
                    } label: {
                        Label("\(store.settings.locationLabel) · \(store.settings.radiusMiles) mi",
                              systemImage: "location.circle")
                            .font(.footnote)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            .sheet(isPresented: $showingLocation) {
                LocationSheet(store: store)
            }
        }
    }

    private var list: some View {
        List {
            Section {
                locationRow
            }

            Section {
                ForEach(store.visibleSummaries) { summary in
                    NavigationLink(value: summary.nctId) {
                        TrialCard(summary: summary)
                    }
                }
            } header: {
                Text("\(store.visibleSummaries.count) trials")
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

extension MatchesView {
    /// A labelled, tappable row rather than only the toolbar icon. The back
    /// button taught us that an unlabelled glyph is easy to miss entirely, and
    /// where you're searching is too important to hide behind one.
    var locationRow: some View {
        Button {
            showingLocation = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "location.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.settings.locationLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("within \(store.settings.radiusMiles) miles · tap to change")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search area: \(store.settings.locationLabel), within \(store.settings.radiusMiles) miles. Tap to change.")
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
                Image(systemName: summary.nearestSiteIsEnrolling
                      ? "mappin.and.ellipse" : "exclamationmark.triangle.fill")
                    .font(.caption2)
                Text(distanceText)
                    .font(.caption)
            }
            .foregroundStyle(summary.nearestSiteIsEnrolling ? Color.secondary : Color.orange)

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
        guard let miles = summary.distanceMiles, let site = summary.nearestSite else {
            return "\(summary.siteCount) site\(summary.siteCount == 1 ? "" : "s"), location unlisted"
        }
        let place = [site.city, site.state].compactMap { $0 }.first ?? "Study site"
        let far = miles >= 20 ? " · \(Int(miles.rounded())) mi" : ""

        // Site counts describe *enrolling* sites, not every site ever listed —
        // "nearest of 85 sites" is misleading when only 82 are open.
        guard summary.nearestSiteIsEnrolling else {
            return "\(place)\(far) — not currently enrolling"
        }
        let open = summary.enrollingSiteCount
        let suffix = open > 1 ? " · nearest of \(open) enrolling sites" : ""
        return "\(place)\(far)\(suffix)"
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
