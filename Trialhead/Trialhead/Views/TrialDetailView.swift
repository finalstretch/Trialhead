import SwiftUI

struct TrialDetailView: View {
    let study: Study
    @Bindable var store: TrialsStore

    @State private var showingContact = false
    /// Optional so the view still works outside the tour (previews, tests).
    @Environment(Tour.self) private var tour: Tour?

    private var profile: Profile { store.profile }
    private var settings: SearchSettings { store.settings }
    private var section: ProtocolSection? { study.protocolSection }
    private var nctId: String { section?.identificationModule?.nctId ?? "" }
    private var evaluation: TrialEvaluation { TrialAnalyzer.evaluate(study, profile: profile) }
    private var parseFailed: Bool { TrialAnalyzer.parseFailed(study) }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    summaryCard
                        .id(TourTarget.questions)
                        .tourAnchor(.questions)
                    contactButton
                        .id(TourTarget.contactButton)
                        .tourAnchor(.contactButton)
                    if !parseFailed {
                        // Anchors live on the individual sections inside, not
                        // here: an `anchorPreference` on a parent replaces
                        // whatever its subtree published, so wrapping the whole
                        // checklist silently erased the colour-key anchor.
                        checklist
                    } else {
                        rawCriteriaFallback
                    }
                    sites
                        .id(TourTarget.siteLocation)
                        .tourAnchor(.siteLocation)
                    provenance
                }
                .padding()
            }
            // Tour targets sit below the fold, so bring each one into view
            // before the spotlight tries to point at it.
            .onChange(of: tour?.step) { _, step in
                guard let target = step?.target, step?.isOnDetailScreen == true else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    scroll.scrollTo(target, anchor: .center)
                }
            }
            .onAppear {
                // Opening a trial is the tour's second interactive step.
                if tour?.step == .openTrial { tour?.completed(.openTrial) }
                // `onChange` doesn't fire when the page opens with the step
                // already set — going Back from Profile, or resuming mid-tour.
                if let target = tour?.step?.target, tour?.step?.isOnDetailScreen == true {
                    scroll.scrollTo(target, anchor: .center)
                }
            }
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
                Text(evaluation.matches == 1
                     ? "1 thing already looks fine"
                     : "\(evaluation.matches) things already look fine")
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
            colourKey
                .id(TourTarget.colourKey)
                .tourAnchor(.colourKey)

            if !evaluation.structured.isEmpty {
                group(title: "From the trial record") {
                    ForEach(Array(evaluation.structured.enumerated()), id: \.offset) { _, check in
                        // Structured rows carry their own explanation in the
                        // text, since "Age" alone says nothing on its own.
                        CriterionRow(verdict: check.verdict,
                                     text: "\(check.label): \(check.rationale)")
                    }
                }
            }

            let inclusion = evaluation.criteria.filter { $0.criterion.kind == .inclusion }
            let exclusion = evaluation.criteria.filter { $0.criterion.kind == .exclusion }

            if !inclusion.isEmpty {
                group(title: "Requirements") {
                    ForEach(Array(inclusion.enumerated()), id: \.offset) { _, item in
                        CriterionRow(verdict: item.verdict,
                                     text: item.criterion.text,
                                     depth: item.criterion.depth,
                                     isHeading: item.criterion.isHeading)
                    }
                }
                .id(TourTarget.requirements)
                .tourAnchor(.requirements)
            }

            if !exclusion.isEmpty {
                group(title: "Disqualifiers") {
                    ForEach(Array(exclusion.enumerated()), id: \.offset) { _, item in
                        CriterionRow(verdict: item.verdict,
                                     text: item.criterion.text,
                                     depth: item.criterion.depth,
                                     isHeading: item.criterion.isHeading)
                    }
                }
            }
        }
    }

    /// Said once, at the top, instead of repeated under all forty rows.
    private var colourKey: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("KEY")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)

            HStack(spacing: 10) {
                keyItem(.match, "Looks fine")
                keyItem(.ask, "Worth asking")
                if evaluation.blockers > 0 { keyItem(.blocker, "Rules you out") }
            }
        }
    }

    private func keyItem(_ verdict: Verdict, _ label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: verdict.symbol)
                .font(.caption)
                .foregroundStyle(verdict.tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(verdict.tint.opacity(0.14), in: Capsule())
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

/// One eligibility rule, marked in green or amber rather than annotated.
///
/// The per-row explanations this replaced ("Bring this one to your care team")
/// repeated identically down forty rows and drowned out the criteria themselves.
/// The colour key at the top of the checklist says it once instead.
struct CriterionRow: View {
    let verdict: Verdict
    let text: String
    var depth: Int = 0
    /// Structural labels render as quiet headings, unmarked — they aren't
    /// rules and shouldn't look like one.
    var isHeading: Bool = false

    @State private var expanded = false

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
        HStack(alignment: .top, spacing: 9) {
            // A shape as well as a colour, so the meaning survives for anyone
            // who can't distinguish green from amber.
            Image(systemName: verdict.symbol)
                .font(.subheadline)
                .foregroundStyle(verdict.tint)
                .padding(.top, 1)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(expanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(verdict.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
        .padding(.leading, CGFloat(depth) * 16)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(verdict.spokenLabel): \(text)")
    }
}

// MARK: - Verdict styling

extension Verdict {
    var tint: Color {
        switch self {
        case .match: return .green
        case .ask: return .orange
        case .blocker: return .red
        }
    }

    var symbol: String {
        switch self {
        case .match: return "checkmark.circle.fill"
        case .ask: return "questionmark.circle.fill"
        case .blocker: return "xmark.circle.fill"
        }
    }

    /// Never encode meaning in colour alone.
    var spokenLabel: String {
        switch self {
        case .match: return "Looks fine"
        case .ask: return "Worth asking"
        case .blocker: return "Rules you out"
        }
    }
}
