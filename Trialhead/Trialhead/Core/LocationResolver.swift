import Foundation
import CoreLocation

/// How the person told us where they are.
enum LocationMode: String, Codable, CaseIterable, Identifiable {
    case zip, city
    var id: String { rawValue }

    var label: String {
        switch self {
        case .zip: return "ZIP code"
        case .city: return "City"
        }
    }

    var prompt: String {
        switch self {
        case .zip: return "e.g. 10021"
        case .city: return "e.g. Boston, MA"
        }
    }
}

struct ResolvedPlace: Equatable {
    let latitude: Double
    let longitude: Double
    let label: String
}

enum LocationError: LocalizedError {
    case empty
    case notFound(String)
    case malformedZip

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Enter a ZIP code or city first."
        case .malformedZip:
            return "A US ZIP code is five digits, like 10021."
        case .notFound(let query):
            return "Couldn't find “\(query)”. Check the spelling, or try the nearest larger city."
        }
    }
}

/// Turns "10021" or "Boston, MA" into coordinates, using Apple's built-in
/// geocoder. No API key and no third-party service — the query goes to Apple,
/// never to us, and it carries no health information.
///
/// US-only for now, matching DESIGN.md §11.4.
enum LocationResolver {

    static func resolve(_ rawQuery: String, mode: LocationMode) async throws -> ResolvedPlace {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw LocationError.empty }

        if mode == .zip {
            let digits = query.filter(\.isNumber)
            guard digits.count == 5 else { throw LocationError.malformedZip }
        }

        // Appending the country stops "Boston" resolving to Boston, Lincolnshire.
        let searchText = mode == .zip ? "\(query), USA" : "\(query), USA"

        let placemarks: [CLPlacemark]
        do {
            placemarks = try await CLGeocoder().geocodeAddressString(searchText)
        } catch {
            throw LocationError.notFound(query)
        }

        guard let best = placemarks.first(where: { $0.location != nil }),
              let coordinate = best.location?.coordinate
        else { throw LocationError.notFound(query) }

        return ResolvedPlace(latitude: coordinate.latitude,
                             longitude: coordinate.longitude,
                             label: describe(best, mode: mode, fallback: query))
    }

    private static func describe(_ placemark: CLPlacemark, mode: LocationMode, fallback: String) -> String {
        let town = placemark.locality ?? placemark.subAdministrativeArea
        let state = placemark.administrativeArea

        switch mode {
        case .zip:
            let zip = placemark.postalCode ?? fallback
            let place = [town, state].compactMap { $0 }.joined(separator: ", ")
            return place.isEmpty ? zip : "\(zip) · \(place)"
        case .city:
            let place = [town, state].compactMap { $0 }.joined(separator: ", ")
            return place.isEmpty ? fallback : place
        }
    }
}
