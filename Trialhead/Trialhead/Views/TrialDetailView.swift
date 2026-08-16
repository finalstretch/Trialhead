import SwiftUI

struct TrialDetailView: View {
    let study: Study
    @Bindable var store: TrialsStore

    @State private var showingContact = false

    private var profile: Profile { store.profile }
    private var settings: SearchSettings { store.settings }
    private var section: ProtocolSection? { study.protocolSection }
    private var nctId: String { section?.identificationModule?.nctId ?? "" }
    private var evaluation: TrialEvaluation { TrialAnalyzer.evaluate(study, profile: profile) }
    private var parseFailed: Bool { TrialAnalyzer.parseFailed(study) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                summaryCard
                contactButton
                if !parseFailed { checklist } else { rawCriteriaFallback }
                sites
                provenance
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.toggleSaved(nctId)
                } label: {
                    Label(store.isSaved(nctId) ? "Saved" : "Save",
                          systemImage: store.isSaved(nctId) ? "bookmark.fill" : "bookmark")
                }
                .tint(store.isSaved(nctId) ? .orange : .accentColor)
            }
        }
        .sheet(isPresented: $showingContact) {
            ContactSheet(study: study, profile: profile, evaluation: evaluation)
        }
        // Deliberately no title: a long NCT number here crowds the navigation bar,
        // and iOS responds by dropping the "Trials" label from the back button,
        // leaving a bare chevron that's genuinely hard to find. The ID lives in
        // the header instead, where there's room for it.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                StatusPill(status: section?.statusModule?.overallStatus ?? "UNKNOWN")
                if let phase = section?.designModule?.phases?.first {
                    Text(phase.replacingOccurrences(of: "PHASE", with: "Phase "))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(section?.identificationModule?.briefTitle ?? "Untitled study")
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)

            if let sponsor = section?.sponsorCollaboratorsModule?.leadSponsor?.name {
                Text(sponsor).font(.subheadline).foregroundStyle(.secondary)
            }

            if let nctId = section?.identificationModule?.nctId {
                Text(nctId)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Summary

    /// Leads with questions, not a score. DESIGN.md §1 — this is a preparation
    /// tool, so a long question list is the product working, not failing.
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("^[\(evaluation.asks) question](inflect: true) to ask")
                .font(.headline)
            if evaluation.matches > 0 {
                Text("\(evaluation.matches) things already look fine")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Most eligibility rules need bloodwork or your doctor's judgement. That's normal — this is your question list, not a verdict.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Placed directly under the summary, above the checklist. The point of the
    /// app is the phone call; burying it below forty rows of criteria would
    /// mean most people never reach it.
    private var contactButton: some View {
        Button {
            showingContact = true
        } label: {
            Label("Contact study team", systemImage: "phone.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: - Checklist

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !evaluation.structured.isEmpty {
                group(title: "From the trial record") {
                    ForEach(Array(evaluation.structured.enumerated()), id: \.offset) { _, check in
                        CriterionRow(glyph: check.verdict,
                                     text: check.label,
                                     detail: check.rationale,
                                     category: nil,
                                     verbatim: nil)
                    }
                }
            }

            let inclusion = evaluation.criteria.filter { $0.criterion.kind == .inclusion }
            let exclusion = evaluation.criteria.filter { $0.criterion.kind == .exclusion }

            if !inclusion.isEmpty {
                group(title: "Requirements") {
                    ForEach(Array(inclusion.enumerated()), id: \.offset) { _, item in
                        CriterionRow(glyph: item.verdict,
                                     text: item.criterion.text,
                                     detail: item.rationale,
                                     category: item.category.label,
                                     verbatim: item.criterion.text,
                                     depth: item.criterion.depth,
                                     isHeading: item.criterion.isHeading)
                    }
                }
            }

            if !exclusion.isEmpty {
                group(title: "Disqualifiers") {
                    ForEach(Array(exclusion.enumerated()), id: \.offset) { _, item in
                        CriterionRow(glyph: item.verdict,
                                     text: item.criterion.text,
                                     detail: item.rationale,
                                     category: item.category.label,
                                     verbatim: item.criterion.text,
                                     depth: item.criterion.depth,
                                     isHeading: item.criterion.isHeading)
                    }
                }
            }
        }
    }

    /// DESIGN.md §11.8 — some sponsors submit criteria as unstructured prose
    /// with no bullets. Never show a half-built checklist; show the original.
    private var rawCriteriaFallback: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Couldn't build a checklist", systemImage: "text.alignleft")
                .font(.headline)
            Text("This study's criteria weren't written in a list format, so here is the original text exactly as the sponsor submitted it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(section?.eligibilityModule?.eligibilityCriteria ?? "No criteria listed.")
                .font(.footnote)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Sites

    private var sites: some View {
        let all = section?.contactsLocationsModule?.locations ?? []
        let nearest = TrialAnalyzer.nearestSite(among: all, to: settings.coordinate)

        let enrolling = TrialAnalyzer.enrollingSiteCount(all)

        return group(title: "Where") {
            if let nearest {
                VStack(alignment: .leading, spacing: 4) {
                    Text(nearest.site.facility ?? "Study site").font(.subheadline.weight(.medium))
                    // City-level only — see the note in TrialCard.distanceText.
                    Text([nearest.site.city, nearest.site.state].compactMap { $0 }.joined(separator: ", ")
                         + (nearest.miles >= 20 ? " · about \(Int(nearest.miles.rounded())) mi" : ""))
                        .font(.caption).foregroundStyle(.secondary)

                    if !nearest.isEnrolling {
                        Label("This site is \(nearest.statusLabel.lowercased()) — ask the study team where else is open.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.top, 2)
                    }
                }
            }
            if all.count > 1 {
                Text(enrolling == all.count
                     ? "\(all.count) sites in total"
                     : "\(enrolling) of \(all.count) sites currently enrolling")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var provenance: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("Source: ClinicalTrials.gov · retrieved \(Date.now.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption2).foregroundStyle(.secondary)
            Text("This app does not determine eligibility. Only the study team can do that.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Helper

    private func group<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Row

struct CriterionRow: View {
    let glyph: Verdict
    let text: String
    let detail: String
    let category: String?
    let verbatim: String?
    var depth: Int = 0

    @State private var expanded = false

    /// Structural labels render as quiet headings, with no verdict dot —
    /// they aren't questions and shouldn't look like one.
    var isHeading: Bool = false

    var body: some View {
        if isHeading {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, CGFloat(depth) * 16)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            row
        }
    }

    private var row: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 3) {
                    Text(text)
                        .font(.subheadline)
                        .lineLimit(expanded ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        if let category {
                            Text(category)
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                        Text(detail).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.leading, CGFloat(depth) * 16)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(accessibilityVerdict): \(text). \(detail)")
    }

    private var color: Color {
        switch glyph {
        case .match: return .green
        case .ask: return .orange
        case .blocker: return .red
        }
    }

    /// Never encode meaning in colour alone.
    private var accessibilityVerdict: String {
        switch glyph {
        case .match: return "Looks fine"
        case .ask: return "To ask"
        case .blocker: return "Rules you out"
        }
    }
}
