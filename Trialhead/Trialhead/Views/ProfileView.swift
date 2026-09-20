import SwiftUI

/// Settings-style for now; the guided first-run flow (§5.1) comes in M5.
/// Everything here stays on the device.
struct ProfileView: View {
    @Bindable var store: TrialsStore
    @State private var confirmingDelete = false
    @FocusState private var focusedField: Field?

    /// The typing fields, so the keyboard's Done button knows what to put away.
    private enum Field { case age, condition, medications, priorTreatments, weight }

    var body: some View {
        NavigationStack {
            Form {
                Section("About you") {
                    LabeledContent("Age") {
                        TextField("Age", value: $store.profile.age, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .age)
                    }
                    Picker("Sex", selection: $store.profile.sex) {
                        Text("Not set").tag(Profile.Sex?.none)
                        Text("Female").tag(Profile.Sex?.some(.female))
                        Text("Male").tag(Profile.Sex?.some(.male))
                    }
                }

                Section {
                    TextField("e.g. breast cancer", text: list(\.conditions), axis: .vertical)
                        .focused($focusedField, equals: .condition)
                } header: {
                    Text("Your condition")
                } footer: {
                    Text("Separate several with commas. Used to recognise rules that mention your diagnosis.")
                }

                Section {
                    TextField("e.g. metformin, pembrolizumab", text: list(\.medications), axis: .vertical)
                        .focused($focusedField, equals: .medications)
                    TextField("e.g. mastectomy, chemotherapy", text: list(\.priorTreatments), axis: .vertical)
                        .focused($focusedField, equals: .priorTreatments)
                } header: {
                    Text("Treatments")
                } footer: {
                    Text("Optional. Lets the app flag rules about treatments you've already had — the ones most worth asking about.")
                }

                // Feet, inches and pounds, matching the setup flow. Stored as
                // metric underneath, because that's how trial criteria are
                // written — but nobody in the US knows their height in cm.
                Section {
                    LabeledContent("Height") {
                        HStack(spacing: 2) {
                            Picker("Feet", selection: heightFeet) {
                                ForEach(3...7, id: \.self) { Text("\($0) ft").tag($0) }
                            }
                            Picker("Inches", selection: heightInches) {
                                ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) }
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    LabeledContent("Weight") {
                        HStack(spacing: 4) {
                            TextField("Pounds", value: weightPounds, format: .number.precision(.fractionLength(0)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($focusedField, equals: .weight)
                            Text("lb").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Body measurements")
                } footer: {
                    if let bmi = store.profile.bmi {
                        Text(String(format: "BMI %.1f — answers BMI rules automatically.", bmi))
                    } else {
                        Text("Optional, but they answer BMI rules that would otherwise need asking.")
                    }
                }

                Section {
                    LabeledContent("Searching near", value: store.settings.locationLabel)
                    LabeledContent("Within", value: "\(store.settings.radiusMiles) miles")
                } header: {
                    Text("Search area")
                } footer: {
                    Text("Change these from the location button on the Trials screen.")
                }

                Section {
                    Picker("Text size", selection: $store.textSize) {
                        ForEach(TextSize.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Display")
                } footer: {
                    Text("\"Match my device\" follows the text size set in iOS Settings. The other options make this app larger without changing anything else on your phone.")
                }

                Section {
                    Toggle("Hide trials that rule me out", isOn: $store.hideIneligible)
                } footer: {
                    Text("Only age and sex requirements, which come from exact fields in the trial record.")
                }

                Section {
                    Button("Delete everything", role: .destructive) { confirmingDelete = true }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("\(LocalStore.fileDescription). There is no account and no server — nothing you type here is ever sent anywhere.")
                }

                Section {
                    LabeledContent("Version", value: Self.versionString)
                } footer: {
                    Text("Quote this if you report a problem — it says which build you're running.")
                }
            }
            .navigationTitle("Profile")
            // Without these there is no way to put the keyboard away: the
            // number pads have no return key at all, and the comma-separated
            // fields are multi-line, so return inserts a newline instead.
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .onDisappear { Task { await store.search() } }
            .confirmationDialog("Delete everything?",
                                isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { store.deleteEverything() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your details and saved trials will be erased from this device. This can't be undone.")
            }
        }
    }

    /// Read from the app bundle, so it can never drift from what was installed.
    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    // Imperial on screen, metric in storage.
    private var heightFeet: Binding<Int> {
        Binding(get: { store.profile.heightFeet ?? 5 },
                set: { store.profile.setHeight(feet: $0, inches: store.profile.heightInches ?? 0) })
    }

    private var heightInches: Binding<Int> {
        Binding(get: { store.profile.heightInches ?? 6 },
                set: { store.profile.setHeight(feet: store.profile.heightFeet ?? 5, inches: $0) })
    }

    private var weightPounds: Binding<Double?> {
        Binding(get: { store.profile.weightPounds.map { ($0).rounded() } },
                set: { store.profile.setWeight(pounds: $0) })
    }

    /// Bridges a `[String]` to a comma-separated text field.
    private func list(_ path: WritableKeyPath<Profile, [String]>) -> Binding<String> {
        Binding(
            get: { store.profile[keyPath: path].joined(separator: ", ") },
            set: { text in
                store.profile[keyPath: path] = text
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            })
    }
}
