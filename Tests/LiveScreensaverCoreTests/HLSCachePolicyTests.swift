import XCTest

@testable import LiveScreensaverCore

final class HLSCachePolicyTests: XCTestCase {

    private let maxAge: TimeInterval = 300
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func signed(expiringAt timestamp: Int) -> String {
        return "https://cdn.example.com/videoplayback/expire/\(timestamp)/id/abc/file/index.m3u8"
    }

    // MARK: - expiryTimestamp

    func testReadsExpiryFromSignedURL() {
        XCTAssertEqual(HLSCachePolicy.expiryTimestamp(in: signed(expiringAt: 1_700_000_500)), 1_700_000_500)
    }

    func testReturnsNilWhenThereIsNoExpirySegment() {
        XCTAssertNil(HLSCachePolicy.expiryTimestamp(in: "https://example.com/live/master.m3u8"))
    }

    func testIgnoresNonNumericExpirySegment() {
        XCTAssertNil(HLSCachePolicy.expiryTimestamp(in: "https://example.com/expire/soon/index.m3u8"))
    }

    // MARK: - isFresh, URL carries its own expiry

    func testSignedURLIsFreshBeforeItsExpiry() {
        XCTAssertTrue(
            HLSCachePolicy.isFresh(
                cachedURL: signed(expiringAt: 1_700_000_500),
                modifiedAt: now, now: now, maxAge: maxAge))
    }

    func testSignedURLIsStaleAfterItsExpiry() {
        XCTAssertFalse(
            HLSCachePolicy.isFresh(
                cachedURL: signed(expiringAt: 1_699_999_500),
                modifiedAt: now, now: now, maxAge: maxAge))
    }

    func testEmbeddedExpiryBeatsAYoungCacheFile() {
        // The URL's own expiry is authoritative: a freshly written cache entry
        // holding an already-expired URL must not be used.
        XCTAssertFalse(
            HLSCachePolicy.isFresh(
                cachedURL: signed(expiringAt: 1_699_999_999),
                modifiedAt: now, now: now, maxAge: maxAge))
    }

    func testEmbeddedExpiryAlsoBeatsAnOldCacheFile() {
        // ...and equally, a long-lived signature stays usable even if the cache
        // entry itself is older than maxAge.
        XCTAssertTrue(
            HLSCachePolicy.isFresh(
                cachedURL: signed(expiringAt: 1_700_003_600),
                modifiedAt: now.addingTimeInterval(-3600), now: now, maxAge: maxAge))
    }

    // MARK: - isFresh, falling back to file age

    func testUnsignedURLIsFreshWithinMaxAge() {
        XCTAssertTrue(
            HLSCachePolicy.isFresh(
                cachedURL: "https://example.com/live/master.m3u8",
                modifiedAt: now.addingTimeInterval(-60), now: now, maxAge: maxAge))
    }

    func testUnsignedURLIsStaleBeyondMaxAge() {
        XCTAssertFalse(
            HLSCachePolicy.isFresh(
                cachedURL: "https://example.com/live/master.m3u8",
                modifiedAt: now.addingTimeInterval(-301), now: now, maxAge: maxAge))
    }
}
