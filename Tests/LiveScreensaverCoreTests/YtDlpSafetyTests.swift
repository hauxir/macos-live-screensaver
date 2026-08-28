import XCTest

@testable import LiveScreensaverCore

final class YtDlpSafetyTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ytdlp-safety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeExecutable(permissions: Int) throws -> String {
        let path = directory.appendingPathComponent("yt-dlp").path
        try "#!/bin/sh\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: permissions)], ofItemAtPath: path)
        return path
    }

    func testAcceptsOwnerOnlyWritableExecutable() throws {
        XCTAssertTrue(isSafeToExecute(try makeExecutable(permissions: 0o755)))
    }

    func testRejectsGroupWritableExecutable() throws {
        // /usr/local/bin is group-writable on some setups, so another account
        // could swap the binary this process then runs.
        XCTAssertFalse(isSafeToExecute(try makeExecutable(permissions: 0o775)))
    }

    func testRejectsWorldWritableExecutable() throws {
        XCTAssertFalse(isSafeToExecute(try makeExecutable(permissions: 0o777)))
    }

    func testRejectsMissingFile() {
        XCTAssertFalse(isSafeToExecute(directory.appendingPathComponent("absent").path))
    }
}
