import SwiftUI

/// DESIGN.md §5.1. One question per screen, each with the reason we're asking —
/// people fill in a field when they can see what it buys them.
///
/// Deliberately does NOT ask for treatments or medications. Those sharpen the
/// results, but they're the highest-friction questions in the app, and asking
/// them of someone who hasn't yet seen what a trial page looks like is how you
/// lose them at setup. They live in Profile, suggested at the end of this flow.
struct OnboardingView: View {
    /// The first run is split in two, with the guided tour in between:
    /// `.welcome` explains what the app is, the tour shows how it works, and
    /// `.setup` then collects details — by which point the person has seen why
    /// each one matters.
    enum Mode { case welcome, setup }

    @Bindable var store: TrialsStore
    let mode: Mode

    @State private var step: Step = .welcome
    @State private var condition = ""
    @State private var age: Int?
    @State private var sex: Profile.Sex?
    @State private var heightFeet = 5
    @State private var heightInches = 6
    @State private var heightSet = false
    @State private var weightPounds: Double?
    @State private var locationMode: LocationMode = .zip
    @State private var locationQuery = ""
    @State private var radius: Double = 25
    @State private var isFinishing = false
    @State private var errorText: String?
    @FocusState private var focused: Bool

    enum Step: Int, CaseIterable {
        case welcome, condition, aboutYou, measurements, location, done

        /// The welcome and closing screens aren't questions, so they don't count.
        var questionIndex: Int? {
            switch self {
            case .welcome, .done: return nil
            default: return rawValue - 1
            }
        }
        static let questionCount = 4
    }

    var body: some View {
        VStack(spacing: 0) {
            if let index = step.questionIndex {
                ProgressDots(current: index, total: Step.questionCount)
                    .padding(.top, 20)
            }

            ScrollView {
                content
                    .padding(.horizontal, 28)
                    .padding(.top, step.questionIndex == nil ? 60 : 36)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            controls
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
        }
        .animation(.easeInOut(duration: 0.22), value: step)
        .interactiveDismissDisabled()
        .onAppear {
            if mode == .setup {
                step = .condition
                // Carry over whatever they searched during the tour.
                if condition.isEmpty { condition = store.settings.condition }
            }
        }
    }

    // MARK: - Screens

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:     welcome
        case .condition:   conditionStep
        case .aboutYou:    aboutYouStep
        case .measurements: measurementsStep
        case .location:    locationStep
        case .done:        doneStep
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            // The app icon itself, so the first screen matches what the person
            // just tapped on their home screen.
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("Trialhead")
                .font(.largeTitle.bold())

            Text("Find clinical trials near you — and know what to ask before you call.")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Bullet(icon: "magnifyingglass",
                       title: "Trials close to home",
                       detail: "Search by ZIP code or city, and set how far you're willing to travel.")
                Bullet(icon: "checklist",
                       title: "Plain-English question lists",
                       detail: "Every trial has pages of eligibility rules. We turn them into the questions worth asking.")
                Bullet(icon: "phone.fill",
                       title: "One tap to the study team",
                       detail: "With a message already written for you. Calling is normal, free, and commits you to nothing.")
            }
            .padding(.top, 8)

            Text("Trialhead can't tell you whether you qualify — only a study team can decide that. It helps you have a better conversation with them.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Text("Next: a quick walkthrough of how it works. You'll add your own details afterwards.")
                .font(.footnote.weight(.medium))
                .padding(.top, 6)
        }
    }

    private var conditionStep: some View {
        Question(title: "What are you looking for trials for?",
                 detail: "A condition name is enough — “breast cancer”, “type 2 diabetes”, “Parkinson's”.") {
            TextField("Condition", text: $condition)
                .textFieldStyle(.plain)
                .font(.title3)
                .autocorrectionDisabled()
                .focused($focused)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) { Divider() }
                .submitLabel(.next)
                .onSubmit { advance() }
        }
    }

    private var aboutYouStep: some View {
        Question(title: "A little about you",
                 detail: "Age and sex are listed as hard requirements by most trials, so these two let us hide the ones that couldn't take you.") {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Age").font(.subheadline).foregroundStyle(.secondary)
                    TextField("Years", value: $age, format: .number)
                        .keyboardType(.numberPad)
                        .font(.title3)
                        .focused($focused)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) { Divider() }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sex").font(.subheadline).foregroundStyle(.secondary)
                    Picker("Sex", selection: $sex) {
                        Text("Female").tag(Profile.Sex?.some(.female))
                        Text("Male").tag(Profile.Sex?.some(.male))
                    }
                    .pickerStyle(.segmented)
                    Text("As recorded on your medical records — that's what trial criteria refer to.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var measurementsStep: some View {
        Question(title: "Your height and weight",
                 detail: "Optional. Many trials set a body-weight range, and these two answer that rule automatically instead of leaving it as a question for your doctor.") {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Height").font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Picker("Feet", selection: $heightFeet) {
                            ForEach(3...7, id: \.self) { Text("\($0) ft").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 110)
                        .clipped()

                        Picker("Inches", selection: $heightInches) {
                            ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 110)
                        .clipped()
                    }
                    .onChange(of: heightFeet) { _, _ in heightSet = true }
                    .onChange(of: heightInches) { _, _ in heightSet = true }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Weight").font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        TextField("Pounds", value: $weightPounds, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.title3)
                            .focused($focused)
                        Text("lb").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Divider() }
                }
            }
        }
    }

    private var locationStep: some View {
        Question(title: "Where are you?",
                 detail: "Used only to measure how far study sites are. It's turned into a map location on your device.") {
            VStack(alignment: .leading, spacing: 24) {
                Picker("Search by", selection: locationModeBinding) {
                    ForEach(LocationMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                TextField(locationMode.prompt, text: $locationQuery)
                    .keyboardType(locationMode == .zip ? .numberPad : .default)
                    .textContentType(locationMode == .zip ? .postalCode : .addressCity)
                    .autocorrectionDisabled()
                    .font(.title3)
                    .focused($focused)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Divider() }
                    .submitLabel(.done)
                    .onSubmit { advance() }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("How far will you travel?")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(radius)) miles").font(.body.weight(.semibold)).monospacedDigit()
                    }
                    Slider(value: $radius,
                           in: Double(SearchSettings.minRadiusMiles)...Double(SearchSettings.maxRadiusMiles),
                           step: 5)
                    Text("Trials often need weekly visits, so we cap this at \(SearchSettings.maxRadiusMiles) miles.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)

            Text("You're set")
                .font(.largeTitle.bold())

            Text("We'll show trials for **\(condition)** within **\(Int(radius)) miles** of **\(store.settings.locationLabel)**.")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Bullet(icon: "person.crop.circle",
                       title: "Add treatments later",
                       detail: "Once you've had a look around, adding past treatments and current medications in Profile makes the question lists much sharper.")
                Bullet(icon: "lock.fill",
                       title: "Nothing leaves your phone",
                       detail: "No account, no server. You can erase everything from Profile at any time.")
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            // Wrapped rather than passed directly: `advance` has a defaulted
            // parameter, so its type is `(Bool) -> Void`, not `() -> Void`.
            Button {
                advance()
            } label: {
                HStack {
                    if isFinishing { ProgressView().controlSize(.small).tint(.white) }
                    Text(primaryLabel)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canAdvance || isFinishing)

            HStack {
                if canGoBack {
                    Button("Back") { retreat() }
                        .font(.subheadline)
                }
                Spacer()
                if isSkippable {
                    Button("Skip") { advance(skipping: true) }
                        .font(.subheadline)
                }
            }
            .frame(minHeight: 22)
        }
    }

    private var primaryLabel: String {
        switch step {
        case .welcome: return "Show me how it works"
        case .location: return isFinishing ? "Finding trials…" : "Find trials"
        case .done: return "Start looking"
        default: return "Continue"
        }
    }

    /// No Back on the first setup question — behind it is the welcome screen
    /// and the whole walkthrough, which belong to an earlier phase.
    private var canGoBack: Bool {
        step != .welcome && step != .done && step != .condition
    }

    /// Height and weight are genuinely optional. Condition and location aren't —
    /// without them there is nothing to search and nowhere to search from.
    private var isSkippable: Bool {
        step == .measurements || step == .aboutYou
    }

    private var canAdvance: Bool {
        switch step {
        case .condition: return !condition.trimmingCharacters(in: .whitespaces).isEmpty
        case .location: return !locationQuery.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }

    private var locationModeBinding: Binding<LocationMode> {
        Binding(get: { locationMode },
                set: { tapped in
                    guard tapped != locationMode else { return }
                    locationMode = tapped
                    locationQuery = ""
                    errorText = nil
                })
    }

    // MARK: - Flow

    private func advance(skipping: Bool = false) {
        focused = false
        errorText = nil

        switch step {
        case .welcome:
            // Hands over to the guided tour; setup resumes when it ends.
            store.hasSeenWelcome = true
        case .location:
            Task { await finishSetup() }
        case .done:
            store.hasCompletedOnboarding = true
        default:
            if skipping { clearCurrentStep() }
            step = Step(rawValue: step.rawValue + 1) ?? .done
        }
    }

    private func retreat() {
        focused = false
        errorText = nil
        step = Step(rawValue: step.rawValue - 1) ?? .welcome
    }

    private func clearCurrentStep() {
        switch step {
        case .aboutYou: age = nil; sex = nil
        case .measurements: heightSet = false; weightPounds = nil
        default: break
        }
    }

    /// Resolves the location, writes everything into the store, then searches.
    /// Only advances if the location resolved — otherwise there's nowhere to
    /// search from and the results screen would be empty for no visible reason.
    private func finishSetup() async {
        isFinishing = true
        defer { isFinishing = false }

        var updated = Profile()
        updated.conditions = [condition.trimmingCharacters(in: .whitespaces)]
        updated.age = age
        updated.sex = sex
        if heightSet { updated.setHeight(feet: heightFeet, inches: heightInches) }
        updated.setWeight(pounds: weightPounds)

        store.profile = updated
        store.settings.condition = condition.trimmingCharacters(in: .whitespaces)

        await store.applyLocation(query: locationQuery, mode: locationMode, radius: Int(radius))

        if let failure = store.locationError {
            errorText = failure
        } else {
            step = .done
        }
    }
}

// MARK: - Small pieces

private struct Question<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title.bold())
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
            content.padding(.top, 16)
        }
    }
}

private struct Bullet: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProgressDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: current)
        .accessibilityLabel("Step \(current + 1) of \(total)")
    }
}
