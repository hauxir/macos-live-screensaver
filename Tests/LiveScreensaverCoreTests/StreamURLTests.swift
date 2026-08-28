import XCTest

@testable import LiveScreensaverCore

final class StreamURLTests: XCTestCase {

    // MARK: - needsYtDlpExtraction

    func testDirectManifestNeedsNoExtraction() {
        XCTAssertFalse(needsYtDlpExtraction("https://example.com/live/master.m3u8"))
    }

    func testManifestWithQueryStringNeedsNoExtraction() {
        XCTAssertFalse(needsYtDlpExtraction("https://example.com/master.m3u8?token=abc"))
    }

    func testYouTubeWatchURLNeedsExtraction() {
        XCTAssertTrue(needsYtDlpExtraction("https://www.youtube.com/watch?v=abc123"))
    }

    func testBareHostNeedsExtraction() {
        XCTAssertTrue(needsYtDlpExtraction("https://example.com"))
    }

    // MARK: - isStreamPlaceURL

    func testRecognisesStreamPlace() {
        XCTAssertTrue(isStreamPlaceURL("https://stream.place/byjp.me"))
    }

    func testRecognisesStreamPlaceSubdomain() {
        XCTAssertTrue(isStreamPlaceURL("https://eu.stream.place/byjp.me"))
    }

    func testIsCaseInsensitiveOnHost() {
        XCTAssertTrue(isStreamPlaceURL("https://Stream.Place/byjp.me"))
    }

    func testDoesNotMatchLookalikeSuffix() {
        // The suffix rule must not match a domain that merely ends in the same
        // characters, e.g. an attacker registering notstream.place.
        XCTAssertFalse(isStreamPlaceURL("https://mystream.place.evil.com/byjp.me"))
    }

    func testDoesNotMatchUnrelatedHost() {
        XCTAssertFalse(isStreamPlaceURL("https://youtube.com/watch?v=abc"))
    }

    // MARK: - getStreamPlaceHLSURL

    func testBuildsPlaybackURLFromUsername() {
        XCTAssertEqual(
            getStreamPlaceHLSURL("https://stream.place/byjp.me")?.absoluteString,
            "https://stream.place/xrpc/place.stream.playback.getLivePlaylist?streamer=byjp.me"
        )
    }

    func testStripsEmbedPrefix() {
        XCTAssertEqual(
            getStreamPlaceHLSURL("https://stream.place/embed/byjp.me")?.absoluteString,
            "https://stream.place/xrpc/place.stream.playback.getLivePlaylist?streamer=byjp.me"
        )
    }

    func testToleratesTrailingSlash() {
        XCTAssertEqual(
            getStreamPlaceHLSURL("https://stream.place/byjp.me/")?.absoluteString,
            "https://stream.place/xrpc/place.stream.playback.getLivePlaylist?streamer=byjp.me"
        )
    }

    func testPreservesSubdomain() {
        XCTAssertEqual(
            getStreamPlaceHLSURL("https://eu.stream.place/byjp.me")?.absoluteString,
            "https://eu.stream.place/xrpc/place.stream.playback.getLivePlaylist?streamer=byjp.me"
        )
    }

    func testRejectsURLWithNoUsername() {
        XCTAssertNil(getStreamPlaceHLSURL("https://stream.place/"))
    }

    func testRejectsEmbedWithNoUsername() {
        XCTAssertNil(getStreamPlaceHLSURL("https://stream.place/embed/"))
    }
}
