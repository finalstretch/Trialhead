import SwiftUI

struct MatchesView: View {
    @Bindable var store: TrialsStore
    /// Owned by ContentView so tapping the Trials tab can pop back to the list.
    @Binding var path: [String]
    @State private var showingLocation = false
    @State private var showPhaseFilter = false

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
                searchRow
                locationRow
            }

            phaseFilterSection

            Section {
                ForEach(Array(store.visibleSummaries.enumerated()), id: \.element.id) { index, summary in
                    NavigationLink(value: summary.nctId) {
                        TrialCard(summary: summary)
                    }
                    // The tour points at the first result when it asks the
                    // person to open one.
                    .modifier(ConditionalAnchor(target: .firstResult, active: index == 0))
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

    /// A plain search field rather than `.searchable`. The system version is
    /// nicer out of the box, but its frame can't be measured, and the guided
    /// tour needs to point at it.
    var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Condition", text: $store.settings.condition)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await store.search() } }
            if !store.settings.condition.isEmpty {
                Button {
                    store.settings.condition = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.secondary.opacity(0.12), in: Capsule())
        .listRowSeparator(.hidden)
        .tourAnchor(.searchBar)
    }

    /// Phase filter. Collapsed by default so it doesn't push the trials off
    /// screen; each row carries a plain-English explanation, because "Phase 1"
    /// is vocabulary and "first testing in people" is information.
    var phaseFilterSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showPhaseFilter) {
                let counts = store.phaseCounts()

                ForEach(TrialPhase.allCases) { phase in
                    let count = counts[phase.rawValue] ?? 0
                    let isOn = store.settings.selectedPhases.contains(phase.rawValue)

                    Button {
                        store.togglePhase(phase)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                                .font(.title3)
                                .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(phase.label)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("\(count)")
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.secondary)
                                }
                                Text(phase.blurb)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? [.isSelected] : [])
                    .accessibilityLabel("\(phase.label), \(count) trials. \(phase.blurb)")
                }

                if !store.settings.selectedPhases.isEmpty {
                    Button("Show all phases") { store.clearPhaseFilter() }
                        .font(.subheadline)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stage of testing")
                        .font(.subheadline.weight(.medium))
                    Text(phaseFilterSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tourAnchor(.phaseFilter)
        } footer: {
            if showPhaseFilter {
                Text("Trials are tested in stages. Earlier phases are more experimental; later ones compare against the treatment you'd normally get. A higher number isn't automatically better — it depends on your situation.")
                    .font(.caption)
            }
        }
    }

    private var phaseFilterSummary: String {
        let selected = store.settings.selectedPhases
        guard !selected.isEmpty else { return "Showing every phase · tap to filter" }
        let names = TrialPhase.allCases
            .filter { selected.contains($0.rawValue) }
            .map(\.label)
        return "Showing " + names.joined(separator: ", ")
    }

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
        .tourAnchor(.locationRow)
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
                Text(summary.phaseDisplay)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
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
