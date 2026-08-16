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
}

// MARK: - The overlay

struct TourOverlay: View {
    @Bindable var store: TrialsStore
    let tour: Tour
    let anchors: [TourTarget: Anchor<CGRect>]
    let proxy: GeometryProxy

    private var step: Tour.Step? { tour.step }

    /// The area to mark. Clamped to the screen: the requirements checklist is
    /// often taller than the display, and a marker running off both edges
    /// wouldn't read as pointing at anything.
    private var spotlight: CGRect? {
        guard let target = step?.target, let anchor = anchors[target] else { return nil }
        let visible = proxy[anchor].insetBy(dx: -8, dy: -8)
            .intersection(CGRect(origin: .zero, size: proxy.size))
        guard !visible.isNull, visible.height > 24 else { return nil }
        return visible
    }

    /// Highlighter blue — light enough that the text underneath stays readable,
    /// which is the whole point of marking something rather than masking it.
    private static let highlighter = Color(red: 0.28, green: 0.64, blue: 1.0)

    var body: some View {
        if let step {
            ZStack {
                touchBlocker
                highlight
                callout(for: step)
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.28), value: step)
        }
    }

    // MARK: Highlight

    /// A translucent blue marker over the component being described. No blur or
    /// dimming anywhere else: the rest of the screen stays perfectly legible, so
    /// the highlighted part reads as *"this one"* rather than as the only thing
    /// that exists.
    @ViewBuilder
    private var highlight: some View {
        if let spotlight {
            RoundedRectangle(cornerRadius: 14)
                .fill(Self.highlighter.opacity(0.22))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Self.highlighter.opacity(0.85), lineWidth: 2.5)
                }
                .frame(width: spotlight.width, height: spotlight.height)
                .position(x: spotlight.midX, y: spotlight.midY)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// Invisible, and only present where wandering off would strand the tour on
    /// the wrong screen. Steps that expect a tap, steps that invite scrolling,
    /// and the two tab steps all leave the app fully usable.
    @ViewBuilder
    private var touchBlocker: some View {
        if let step, step.target != nil, !step.waitsForAction, !step.allowsScrolling {
            Color.clear.contentShape(Rectangle())
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

                HStack(spacing: 14) {
                    if tour.canRetreat {
                        Button {
                            tour.retreat()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                                .font(.subheadline)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    Spacer()
                    Button("Skip") { tour.skip() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if step.waitsForAction {
                        Label("Your turn", systemImage: "hand.tap.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.tint)
                    } else {
                        Button(step.buttonLabel) { tour.advance() }
                            .buttonStyle(.borderedProminent)
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
