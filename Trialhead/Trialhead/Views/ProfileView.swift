import SwiftUI

/// Minimal for now — real onboarding comes later (DESIGN.md §5.1).
/// Everything here stays on the device.
struct ProfileView: View {
    @Bindable var store: TrialsStore

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
                        Text(String(format: "BMI %.1f — used to answer BMI rules automatically.", bmi))
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
                    Text("Nothing here leaves your phone. There is no account and no server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profile")
            .onDisappear { Task { await store.search() } }
        }
    }
}
