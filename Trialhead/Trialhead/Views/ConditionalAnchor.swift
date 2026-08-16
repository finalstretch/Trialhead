import SwiftUI

/// Applies a tour anchor only to a specific row — used for "the first result",
/// where the same view builder produces every card.
struct ConditionalAnchor: ViewModifier {
    let target: TourTarget
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.tourAnchor(target)
        } else {
            content
        }
    }
}
