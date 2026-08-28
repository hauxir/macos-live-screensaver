import Foundation

// MARK: - yt-dlp discovery

let ytdlpPaths = [
    "/opt/homebrew/bin/yt-dlp",
    "/usr/local/bin/yt-dlp",
    "/opt/local/bin/yt-dlp",
    (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/yt-dlp"),
]

/// Whether a binary is safe for a screensaver to execute.
///
/// Two of the searched locations are writable without admin rights on a default
/// install (`/usr/local/bin`, `~/.local/bin`). Anything group- or world-writable
/// can be swapped by another account for something this process would then run,
/// so refuse it rather than execute it.
func isSafeToExecute(_ path: String) -> Bool {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value,
        let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value
    else {
        return false
    }
    // Owned by root, or by whoever is running the screensaver.
    guard owner == 0 || owner == getuid() else { return false }
    // Not writable by group or other.
    return permissions & 0o022 == 0
}

/// Whether a yt-dlp exists at all, regardless of whether it is safe to run.
/// Lets the failure be reported as "unsafe" rather than "not installed".
func ytDlpIsInstalled() -> Bool {
    return ytdlpPaths.contains { FileManager.default.isExecutableFile(atPath: $0) }
}

func findYtDlpPath() -> String? {
    for path in ytdlpPaths where FileManager.default.isExecutableFile(atPath: path) {
        if isSafeToExecute(path) {
            return path
        }
        Log.extraction.error(
            "Refusing to run \(path, privacy: .public): writable by group or other")
    }
    return nil
}

/// Looked up once per process. yt-dlp breaks against YouTube often enough that
/// "which version" is the first question worth asking about a broken stream.
let ytdlpVersion: String = {
    guard let path = findYtDlpPath() else { return "not installed" }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = ["--version"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    do {
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let version = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (version?.isEmpty == false) ? version! : "unknown"
    } catch {
        return "unknown"
    }
}()
