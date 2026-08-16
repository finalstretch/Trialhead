import SwiftUI

// MARK: - Publishing where things are

/// Collects the on-screen position of every view marked with `.tourAnchor(_:)`.
struct TourAnchorKey: PreferenceKey {
    static var defaultValue: [TourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: Anchor<CGRect>],
                       nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

extension View {
    /// Marks this view as something the tour can point at.
    func tourAnchor(_ target: TourTarget) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [target: $0] }
    }

    /// Blurs everything *except* the given shape.
    func spotlightMask<S: Shape>(_ shape: S, in rect: CGRect) -> some View {
        mask {
            Rectangle()
                .overlay {
                    shape
                        .path(in: rect)
                        .fill(style: FillStyle(eoFill: true))
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
        }
    }
}

// MARK: - The overlay

struct TourOverlay: View {
    @Bindable var store: TrialsStore
    let tour: Tour
    let anchors: [TourTarget: Anchor<CGRect>]
    let proxy: GeometryProxy

    private var step: Tour.Step? { tour.step }

    /// The area to keep sharp. Nil for the closing step, which dims everything.
    private var spotlight: CGRect? {
        guard let target = step?.target, let anchor = anchors[target] else { return nil }
        return proxy[anchor].insetBy(dx: -8, dy: -8)
    }

    var body: some View {
        if let step {
            ZStack {
                backdrop
                callout(for: step)
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.28), value: step)
        }
    }

    // MARK: Backdrop

    @ViewBuilder
    private var backdrop: some View {
        if let spotlight {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.28))
                .spotlightMask(RoundedRectangle(cornerRadius: 16), in: spotlight)
                .allowsHitTesting(!(step?.waitsForAction ?? false))
                .overlay {
                    // A ring so the cut-out reads as deliberate rather than as
                    // a rendering glitch.
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                        .frame(width: spotlight.width, height: spotlight.height)
                        .position(x: spotlight.midX, y: spotlight.midY)
                        .allowsHitTesting(false)
                }
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.28))
        }
    }

    // MARK: Callout

    private func callout(for step: Tour.Step) -> some View {
        VStack {
            if placeCalloutBelow { Spacer(minLength: 0) }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(step.title).font(.headline)
                    Spacer()
                    Text(progressLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Text(step.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if step == .pickCondition { conditionChoices }

                HStack {
                    if !step.waitsForAction {
                        Button("Skip tour") { tour.skip() }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !step.waitsForAction {
                        Button(step.buttonLabel) { tour.advance() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Label("Your turn", systemImage: "hand.tap.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.top, 2)
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.quaternary))
            .shadow(radius: 18, y: 6)
            .padding(.horizontal, 18)

            if !placeCalloutBelow { Spacer(minLength: 0) }
        }
        .padding(.vertical, 60)
    }

    /// Keep the callout away from whatever is being highlighted: if the target
    /// sits in the top half, put the card below it, and vice versa.
    private var placeCalloutBelow: Bool {
        guard let spotlight else { return false }
        return spotlight.midY < proxy.size.height / 2
    }

    private var progressLabel: String {
        guard let step else { return "" }
        return "\(step.rawValue + 1) of \(Tour.Step.allCases.count)"
    }

    private var conditionChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Tour.sampleConditions, id: \.self) { condition in
                Button {
                    store.settings.condition = condition
                    Task {
                        await store.search()
                        tour.completed(.pickCondition)
                    }
                } label: {
                    HStack {
                        Text(condition)
                        Spacer()
                        Image(systemName: "magnifyingglass").font(.caption)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
