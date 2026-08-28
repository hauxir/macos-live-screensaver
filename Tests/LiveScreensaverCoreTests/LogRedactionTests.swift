import XCTest

@testable import LiveScreensaverCore

final class LogRedactionTests: XCTestCase {

    func testKeepsSchemeHostAndPath() {
        XCTAssertEqual(
            Log.redact("https://example.com/live/master.m3u8"),
            "https://example.com/live/master.m3u8"
        )
    }

    func testStripsQueryString() {
        // Extracted stream URLs carry signed tokens here. Logging them would put
        // working credentials into anything a user pastes into an issue.
        XCTAssertEqual(
            Log.redact("https://cdn.example.com/index.m3u8?token=SECRET&sig=ALSOSECRET"),
            "https://cdn.example.com/index.m3u8?<redacted>"
        )
    }

    func testStripsFragment() {
        XCTAssertEqual(
            Log.redact("https://example.com/index.m3u8#SECRET"),
            "https://example.com/index.m3u8"
        )
    }

    func testMarksQueryPresenceOnlyWhenThereIsOne() {
        XCTAssertFalse(Log.redact("https://example.com/a.m3u8").contains("redacted"))
    }
}
