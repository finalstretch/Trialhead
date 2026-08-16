import SwiftUI

/// Where to search from, and how far the person is willing to travel.
///
/// Three controls: search by ZIP code, search by city, and a radius capped at
/// 30 miles. The cap is a product decision, not a technical limit — most trials
/// need repeat in-person visits, so listing something 200 miles away sets
/// someone up to drop out later. See `SearchSettings.maxRadiusMiles`.
struct LocationSheet: View {
    @Bindable var store: TrialsStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: LocationMode = .city
    @State private var query: String = ""
    @State private var radius: Double = 25
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Search by", selection: modeBinding) {
                        ForEach(LocationMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    TextField(mode.prompt, text: $query)
                        .keyboardType(mode == .zip ? .numberPad : .default)
                        .textContentType(mode == .zip ? .postalCode : .addressCity)
                        .autocorrectionDisabled()
                        .focused($fieldFocused)
                        .submitLabel(.search)
                        .onSubmit { apply() }
                } header: {
                    Text("Where are you?")
                } footer: {
                    Text("Used only to measure distance to study sites. It's converted to a map location on your device and never sent with any of your health details.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Within")
                            Spacer()
                            Text("\(Int(radius)) miles")
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                        }
                        Slider(value: $radius,
                               in: Double(SearchSettings.minRadiusMiles)...Double(SearchSettings.maxRadiusMiles),
                               step: 5) {
                            Text("Travel radius")
                        } minimumValueLabel: {
                            Text("\(SearchSettings.minRadiusMiles)").font(.caption2)
                        } maximumValueLabel: {
                            Text("\(SearchSettings.maxRadiusMiles)").font(.caption2)
                        }
                    }
                } header: {
                    Text("How far will you travel?")
                } footer: {
                    Text("Capped at \(SearchSettings.maxRadiusMiles) miles. Trials often need weekly visits, and travel is one of the most common reasons people stop taking part.")
                }

                if let error = store.locationError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button {
                        apply()
                    } label: {
                        HStack {
                            if store.isResolvingLocation {
                                ProgressView().controlSize(.small)
                            }
                            Text(store.isResolvingLocation ? "Finding…" : "Search here")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || store.isResolvingLocation)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Search area")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                mode = store.settings.locationMode
                query = store.settings.locationQuery
                radius = Double(store.settings.radiusMiles)
                store.locationError = nil
            }
        }
    }

    /// Switching mode clears the field, so a ZIP can't sit there while the
    /// picker says City and then fail to resolve for no visible reason.
    ///
    /// This lives in the binding rather than `.onChange(of: mode)` on purpose:
    /// `onAppear` restores the saved mode, which counts as a change, and the
    /// `onChange` version fired afterwards and wiped the value just restored.
    /// A binding only runs when something actually sets it — i.e. a real tap.
    private var modeBinding: Binding<LocationMode> {
        Binding(
            get: { mode },
            set: { tapped in
                guard tapped != mode else { return }
                mode = tapped
                query = ""
                store.locationError = nil
                fieldFocused = true
            })
    }

    private func apply() {
        Task {
            await store.applyLocation(query: query, mode: mode, radius: Int(radius))
            if store.locationError == nil { dismiss() }
        }
    }
}
