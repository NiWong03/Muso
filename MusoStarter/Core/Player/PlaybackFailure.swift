import Foundation

/// Keep useful error codes without exposing signed media URLs or opaque userInfo.
enum PlaybackFailure {
    static func message(for error: Error?) -> String {
        guard let error = error as NSError? else {
            return "Audio playback failed. Tap the search result again to request a fresh stream."
        }
        var details = "\(error.domain) \(error.code)"
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            details += "; \(underlying.domain) \(underlying.code)"
        }
        return "Audio playback failed. Tap the search result again to request a fresh stream. (\(details))"
    }
}
