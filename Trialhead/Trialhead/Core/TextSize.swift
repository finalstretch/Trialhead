import Foundation

/// How large the app draws its text.
///
/// iOS already has a system-wide text size and `.device` follows it, which is
/// the right default. The larger options exist because the people reading this
/// app are often older or unwell, and "go to Settings, change it, come back"
/// is a trip many won't make.
///
/// No SwiftUI import on purpose (DESIGN.md §9) — `Core/` stays free of UI
/// framework code, so turning this into a real font size happens in `Views/`.
enum TextSize: String, Codable, CaseIterable, Identifiable {
    case device, large, larger, largest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .device:  return "Match my device"
        case .large:   return "Large"
        case .larger:  return "Larger"
        case .largest: return "Largest"
        }
    }
}
