import Foundation

enum StreamError {
    case ytDlpMissing
    case ytDlpUnsafe
    case extractionFailed
    case invalidConfiguredURL
    case streamUnavailable
    case noNetwork
    case retriesExhausted

    var reason: String {
        switch self {
        case .ytDlpMissing:
            return "YouTube streams need yt-dlp. Install it with: brew install yt-dlp"
        case .ytDlpUnsafe:
            return "Found yt-dlp, but other users can modify it, so it wasn't run."
        case .extractionFailed:
            return "Couldn't read the stream address for this URL."
        case .invalidConfiguredURL:
            return "That URL doesn't look like a stream. Check it in Options."
        case .streamUnavailable:
            return "The stream is offline or has ended."
        case .noNetwork:
            return "No internet connection."
        case .retriesExhausted:
            return "The stream kept dropping out. It may be having problems."
        }
    }
}

/// Manages a single AVPlayer instance shared across all screensaver views.
