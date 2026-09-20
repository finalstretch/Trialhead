import SwiftUI

/// DESIGN.md §5.6. The friction this removes is the entire point of the app:
/// most people don't know that calling a study coordinator is normal, expected,
/// and welcome — so they never do it.
struct ContactSheet: View {
    let study: Study
    let profile: Profile
    let evaluation: TrialEvaluation

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    @FocusState private var editingDraft: Bool

    private var section: ProtocolSection? { study.protocolSection }
    private var nctId: String { section?.identificationModule?.nctId ?? "" }

    /// Site contacts first — they're usually closer to the actual screening
    /// than the central number — then the central contact as a fallback.
    private var contacts: [(name: String, contact: Contact)] {
        var found: [(String, Contact)] = []
        // The same coordinator is very often listed both against a site and as
        // the central contact. Deduplicate on phone+email so one person doesn't
        // appear twice under two different headings.
        var seen = Set<String>()

        func add(_ heading: String, _ contact: Contact) {
            guard contact.phone != nil || contact.email != nil else { return }
            let key = "\(contact.phone ?? "")|\(contact.email ?? "")"
            guard seen.insert(key).inserted else { return }
            found.append((heading, contact))
        }

        // Site contacts first — they're usually closer to the actual screening.
        for site in section?.contactsLocationsModule?.locations ?? [] {
            for contact in site.contacts ?? [] where contact.role == "CONTACT" {
                add(site.facility ?? site.city ?? "Study site", contact)
            }
        }
        for contact in section?.contactsLocationsModule?.centralContacts ?? [] {
            add("Central study contact", contact)
        }
        return Array(found.prefix(4))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Research coordinators are there to answer exactly these questions. Calling is normal, free, and doesn't commit you to anything.")
                        .font(.subheadline)
                }

                if contacts.isEmpty {
                    Section {
                        Text("This study didn't publish a contact. Your own doctor can usually reach the study team, and the trial ID below is all they need.")
                            .font(.subheadline)
                        LabeledContent("Trial ID", value: nctId)
                    }
                }

                ForEach(Array(contacts.enumerated()), id: \.offset) { _, entry in
                    Section(entry.name) {
                        if let name = entry.contact.name {
                            Text(name).font(.subheadline.weight(.medium))
                        }
                        if let phone = entry.contact.phone, let url = telURL(phone) {
                            Link(destination: url) {
                                Label(phone, systemImage: "phone.fill")
                            }
                        }
                        if let email = entry.contact.email, let url = mailtoURL(email) {
                            Link(destination: url) {
                                Label("Email — draft prepared", systemImage: "envelope.fill")
                            }
                        }
                    }
                }

                Section {
                    TextEditor(text: $draft)
                        .focused($editingDraft)
                        .frame(minHeight: 170)
                        .font(.footnote)
                } header: {
                    Text("Drafted message")
                } footer: {
                    Text("Edit anything you like. Tapping an email link above opens this in Mail. Nothing is sent automatically.")
                }
            }
            .navigationTitle("Contact study team")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                // "Close" rather than "Done": with a Done above the keyboard as
                // well, two buttons of the same name did different things — one
                // put the keyboard away, the other threw away the sheet.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editingDraft = false }
                }
            }
            .onAppear { if draft.isEmpty { draft = defaultDraft } }
        }
    }

    // MARK: - The draft

    /// Built from the profile and the parsed criteria, so the person arrives
    /// with specifics rather than "I saw your study online."
    private var defaultDraft: String {
        var lines: [String] = ["Hello,", ""]
        lines.append("I'm interested in your study \(nctId)"
                     + (section?.identificationModule?.briefTitle
                        .map { " (\($0.trimmingCharacters(in: CharacterSet(charactersIn: ". "))))" } ?? "")
                     + ".")

        var about: [String] = []
        if let age = profile.age { about.append("\(age) years old") }
        if let sex = profile.sex { about.append(sex.rawValue) }
        if !profile.conditions.isEmpty {
            about.append("living with \(profile.conditions.joined(separator: " and "))")
        }
        if !about.isEmpty {
            lines.append("")
            lines.append("A little about me: I'm \(about.joined(separator: ", ")).")
        }
        if !profile.priorTreatments.isEmpty || !profile.medications.isEmpty {
            let treatments = (profile.priorTreatments + profile.medications).joined(separator: ", ")
            lines.append("Treatments so far: \(treatments).")
        }

        lines.append("")
        lines.append("Could you tell me whether I might be a candidate for pre-screening, and what the next step would be?")

        if !topQuestions.isEmpty {
            lines.append("")
            lines.append("A few things I wasn't sure about:")
            for question in topQuestions { lines.append("- \(question)") }
        }

        lines.append("")
        lines.append("Thank you for your time.")
        return lines.joined(separator: "\n")
    }

    /// The most answerable of the amber rows. Capped, because a coordinator
    /// facing forty bullet points answers none of them.
    private var topQuestions: [String] {
        let priority: [Category] = [.priorTherapy, .labValue, .performanceStatus, .diagnosis]
        return evaluation.criteria
            .filter { $0.verdict == .ask && !$0.criterion.isHeading }
            .filter { priority.contains($0.category) }
            .sorted { lhs, rhs in
                (priority.firstIndex(of: lhs.category) ?? 99) < (priority.firstIndex(of: rhs.category) ?? 99)
            }
            .prefix(4)
            .map { $0.criterion.text.prefix(150).trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Links

    private func telURL(_ phone: String) -> URL? {
        URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })")
    }

    private func mailtoURL(_ email: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Question about study \(nctId)"),
            URLQueryItem(name: "body", value: draft.isEmpty ? defaultDraft : draft),
        ]
        return components.url
    }
}
