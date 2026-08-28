import Foundation
import OSLog

// MARK: - Logging

// A screensaver cannot be debugged interactively: it exits the moment you touch
// the machine, and it runs inside a system host process you did not launch.
// Logging is the only diagnostic channel, so it is worth doing properly.
// Users can collect these with Console.app, filtering on this subsystem.
enum Log {
    private static let subsystem = "me.byjp.livescreensaver"

    static let player = Logger(subsystem: subsystem, category: "player")
    static let extraction = Logger(subsystem: subsystem, category: "extraction")
    static let config = Logger(subsystem: subsystem, category: "config")

    /// Stream URLs routinely carry signed tokens and expiry signatures in their
    /// query strings. Log enough to identify the stream, never enough to share
    /// someone's credentials in a bug report.
    static func redact(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else { return "<unparseable url>" }
        let hadQuery = components.query != nil
        components.query = nil
        components.fragment = nil
        let base = components.string ?? "<unparseable url>"
        return hadQuery ? base + "?<redacted>" : base
    }
}

// The preferences domain for ScreenSaverDefaults. This deliberately does NOT
// match CFBundleIdentifier (me.byjp.livescreensaver): changing it would orphan
// the settings of everyone who already has the screensaver installed, since
// their configured URL lives under this name. Migrate the stored values before
