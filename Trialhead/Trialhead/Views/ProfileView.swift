import SwiftUI

/// Settings-style for now; the guided first-run flow (§5.1) comes in M5.
/// Everything here stays on the device.
struct ProfileView: View {
    @Bindable var store: TrialsStore
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("About you") {
                    LabeledContent("Age") {
                        TextField("Age", value: $store.profile.age, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Sex", selection: $store.profile.sex) {
                        Text("Not set").tag(Profile.Sex?.none)
                        Text("Female").tag(Profile.Sex?.some(.female))
                        Text("Male").tag(Profile.Sex?.some(.male))
                    }
                }

                Section {
                    TextField("e.g. breast cancer", text: list(\.conditions), axis: .vertical)
                } header: {
                    Text("Your condition")
                } footer: {
                    Text("Separate several with commas. Used to recognise rules that mention your diagnosis.")
                }

                Section {
                    TextField("e.g. metformin, pembrolizumab", text: list(\.medications), axis: .vertical)
                    TextField("e.g. mastectomy, chemotherapy", text: list(\.priorTreatments), axis: .vertical)
                } header: {
                    Text("Treatments")
                } footer: {
                    Text("Optional. Lets the app flag rules about treatments you've already had — the ones most worth asking about.")
                }

                Section {
                    LabeledContent("Height (cm)") {
                        TextField("cm", value: $store.profile.heightCM, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Weight (kg)") {
                        TextField("kg", value: $store.profile.weightKG, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
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

                Section("Search area") {
                    Picker("Within", selection: $store.settings.radiusMiles) {
                        ForEach([25, 50, 100, 250], id: \.self) { Text("\($0) miles").tag($0) }
                    }
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
            }
            .navigationTitle("Profile")
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
