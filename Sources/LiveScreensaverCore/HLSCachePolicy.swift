import Foundation

// MARK: - Cached stream URL freshness

/// Decides whether a previously extracted stream URL is still worth using.
///
/// Extracted URLs are short-lived. Most carry their own expiry in the path
/// (`.../expire/1735689600/...`), which is authoritative and worth preferring
/// over anything we infer. When there is no expiry to read, the age of the cache
/// file is the fallback.
///
/// Kept free of file I/O so the policy can be tested directly.
enum HLSCachePolicy {
    private static let expirationRegex = try? NSRegularExpression(
        pattern: "expire/([0-9]+)", options: [])

    /// The Unix timestamp embedded in a signed stream URL, if it has one.
    static func expiryTimestamp(in url: String) -> TimeInterval? {
        guard let regex = expirationRegex,
            let match = regex.firstMatch(
                in: url, options: [], range: NSRange(url.startIndex..., in: url)),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: url)
        else {
            return nil
        }
        return TimeInterval(String(url[range]))
    }

    /// Whether a cached URL may still be used.
    ///
    /// - Parameters:
    ///   - cachedURL: the URL as it was written to the cache.
    ///   - modifiedAt: when the cache entry was last written.
    ///   - now: the current time, injected so this can be tested.
    ///   - maxAge: how long an entry without its own expiry stays usable.
    static func isFresh(
        cachedURL: String,
        modifiedAt: Date,
        now: Date = Date(),
        maxAge: TimeInterval
    ) -> Bool {
        if let expiry = expiryTimestamp(in: cachedURL) {
            return expiry > now.timeIntervalSince1970
        }
        return now.timeIntervalSince(modifiedAt) < maxAge
    }
}
