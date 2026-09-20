import Foundation

/// Turns a thrown error into one sentence a patient can act on.
///
/// The search used to display `"\(error)"`, which renders Swift's *internal*
/// description. Someone who lost signal was shown
/// `URLError(_nsError: Error Domain=NSURLErrorDomain Code=-1009 "(null)")`,
/// and an API failure put the whole request URL — search terms included —
/// on screen. Neither tells a reader what to do next.
enum FriendlyError {

    static func message(for error: Error) -> String {
        switch error {
        case let error as URLError:  return message(for: error)
        case let error as SpikeError: return message(for: error)
        case is DecodingError:        return unreadableReply
        default:                      return "Something went wrong. Try again in a moment."
        }
    }

    private static let unreadableReply =
        "ClinicalTrials.gov sent back something this app couldn't read. "
        + "That's usually temporary — try again in a moment."

    private static func message(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet:
            return "No internet connection. Check your Wi-Fi or mobile data, then try again."
        case .dataNotAllowed:
            return "Mobile data is turned off for Trialhead. Turn it on in Settings, or join a Wi-Fi network."
        case .timedOut:
            return "That took too long to load. ClinicalTrials.gov may be busy — try again in a moment."
        case .networkConnectionLost:
            return "The connection dropped part-way through loading. Try again."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "Couldn't reach ClinicalTrials.gov. The service may be temporarily unavailable."
        default:
            return "Couldn't load trials just now. Try again in a moment."
        }
    }

    /// The URL is deliberately dropped from every case — it carries the search
    /// terms, and a web address on screen helps nobody reading this.
    private static func message(for error: SpikeError) -> String {
        switch error {
        case let .http(status, _) where status == 429:
            return "ClinicalTrials.gov is asking us to slow down. Wait a minute, then try again."
        case let .http(status, _) where (500...599).contains(status):
            return "ClinicalTrials.gov is having trouble right now. Try again in a few minutes."
        case .http:
            return "ClinicalTrials.gov couldn't answer that search. Try a different condition."
        case .decoding:
            return unreadableReply
        case let .usage(message):
            return message
        }
    }
}
