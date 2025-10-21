import ScreenSaver
import AVFoundation
import CryptoKit
import Cocoa
import Quartz

private let ModuleName = "com.livescreensaver.app"
private let URLKey = "HLSStreamURL"
private let StreamStartTimeKey = "StreamStartTime"
private let DefaultURL = "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_example_hevc/master.m3u8"

class LiveScreensaverView: ScreenSaverView {

    private var playerLayer: AVPlayerLayer?
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var statusObservation: NSKeyValueObservation?
    private let defaults = ScreenSaverDefaults(forModuleWithName: ModuleName)!
    private let cacheExpirationSeconds: TimeInterval = 300
    private let extractionTimeoutSeconds: TimeInterval = 15
    private var retryCount = 0
    private let maxRetries = 3
    private var stallDetectionTime: Date?
    private let stallTimeoutSeconds: TimeInterval = 10
    private var currentSourceURL: String?
    private var startTime = Date()

    private static let expirationRegex = try? NSRegularExpression(pattern: "expire/([0-9]+)", options: [])
    private static let preferredTimescale: CMTimeScale = 600

    private func getSystemIdleTime() -> TimeInterval {
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved)
    }

    private func isScreenLocked() -> Bool {
        guard let sessionDict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }

        if let isLocked = sessionDict["CGSSessionScreenIsLocked"] as? Bool {
            return isLocked
        }

        return false
    }

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setupScreensaver()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupScreensaver()
    }

    private func needsYtDlpExtraction(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let path = url.path.split(separator: "/").last else {
            return true
        }
        return !path.contains(".m3u8")
    }

    private func md5Hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }

    private func getCacheFilePath(for url: String) -> String {
        let hash = md5Hash(url)
        return (NSTemporaryDirectory() as NSString).appendingPathComponent("screensaver_\(hash)")
    }

    private func extractExpirationTimestamp(from url: String) -> TimeInterval? {
        guard let regex = Self.expirationRegex,
              let match = regex.firstMatch(in: url, options: [], range: NSRange(url.startIndex..., in: url)),
              match.numberOfRanges > 1 else {
            return nil
        }

        let timestampRange = match.range(at: 1)
        guard let range = Range(timestampRange, in: url) else {
            return nil
        }

        let timestampString = String(url[range])
        return TimeInterval(timestampString)
    }

    private func getCachedHLSURL(for sourceURL: String) -> String? {
        let cacheFile = getCacheFilePath(for: sourceURL)

        guard FileManager.default.fileExists(atPath: cacheFile) else {
            return nil
        }

        do {
            let cachedURL = try String(contentsOfFile: cacheFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let expirationTimestamp = extractExpirationTimestamp(from: cachedURL) {
                let currentTimestamp = Date().timeIntervalSince1970
                let timeUntilExpiration = expirationTimestamp - currentTimestamp

                if timeUntilExpiration > 0 {
                    return cachedURL
                } else {
                    try? FileManager.default.removeItem(atPath: cacheFile)
                    return nil
                }
            }

            let attributes = try FileManager.default.attributesOfItem(atPath: cacheFile)
            guard let modificationDate = attributes[.modificationDate] as? Date else {
                return nil
            }

            let age = Date().timeIntervalSince(modificationDate)
            if age < cacheExpirationSeconds {
                return cachedURL
            } else {
                try? FileManager.default.removeItem(atPath: cacheFile)
                return nil
            }
        } catch {
            return nil
        }
    }

    private func cacheHLSURL(_ url: String, for sourceURL: String) {
        let cacheFile = getCacheFilePath(for: sourceURL)
        do {
            try url.write(toFile: cacheFile, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Failed to cache HLS URL: \(error)")
        }
    }

    private func getExtractionLockPath(for url: String) -> String {
        let hash = md5Hash(url)
        return (NSTemporaryDirectory() as NSString).appendingPathComponent("screensaver_\(hash)_lock")
    }

    private func extractHLSURL(_ sourceURL: String, forceRefresh: Bool = false) -> String? {
        if !forceRefresh, let cachedURL = getCachedHLSURL(for: sourceURL) {
            return cachedURL
        }

        let lockFile = getExtractionLockPath(for: sourceURL)

        if FileManager.default.fileExists(atPath: lockFile) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: lockFile)
                if let lockTimestamp = attributes[.modificationDate] as? Date {
                    let lockAge = Date().timeIntervalSince(lockTimestamp)

                    if lockAge < extractionTimeoutSeconds {
                        return nil
                    } else {
                        try? FileManager.default.removeItem(atPath: lockFile)
                    }
                }
            } catch {
                NSLog("Failed to check lock file attributes: \(error)")
            }
        }

        do {
            try "".write(toFile: lockFile, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Failed to create lock file: \(error)")
        }

        let task = Process()

        let ytdlpPaths = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/opt/local/bin/yt-dlp",
            (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/yt-dlp")
        ]

        guard let executablePath = ytdlpPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            try? FileManager.default.removeItem(atPath: lockFile)
            return nil
        }

        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = ["-g", sourceURL]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        var extractedURL: String?

        do {
            try task.run()
            task.waitUntilExit()

            try? pipe.fileHandleForWriting.close()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty,
               let firstURL = output.components(separatedBy: .newlines).first {
                cacheHLSURL(firstURL, for: sourceURL)
                extractedURL = firstURL
            }
        } catch {
            NSLog("Failed to execute yt-dlp: \(error)")
        }

        try? FileManager.default.removeItem(atPath: lockFile)

        return extractedURL
    }

    private func setupScreensaver() {
        animationTimeInterval = 1.0 / 30.0

        let originalURLString = defaults.string(forKey: URLKey) ?? DefaultURL

        var urlString = originalURLString

        if needsYtDlpExtraction(originalURLString) {
            currentSourceURL = originalURLString

            if let cachedURL = getCachedHLSURL(for: originalURLString) {
                urlString = cachedURL

                DispatchQueue.global(qos: .background).async { [weak self] in
                    _ = self?.extractHLSURL(originalURLString, forceRefresh: true)
                }
            } else {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    if let hlsURL = self?.extractHLSURL(originalURLString) {
                        DispatchQueue.main.async {
                            if let url = URL(string: hlsURL) {
                                self?.loadVideo(url: url)
                            }
                        }
                    }
                }
                return
            }
        }

        guard let url = URL(string: urlString) else {
            return
        }

        loadVideo(url: url)
    }

    private func loadVideo(url: URL) {
        // Clean up old observers if reloading
        NotificationCenter.default.removeObserver(self)
        statusObservation?.invalidate()

        playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        player?.volume = 0.0
        player?.automaticallyWaitsToMinimizeStalling = false

        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.frame = bounds
        playerLayer?.videoGravity = .resizeAspectFill

        wantsLayer = true
        if let layer = playerLayer {
            self.layer?.addSublayer(layer)
        }

        statusObservation = playerItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .readyToPlay {
                self?.synchronizePlayback()
                self?.stallDetectionTime = nil
                self?.retryCount = 0
            } else if item.status == .failed {
                self?.handlePlaybackFailure()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemStalled),
            name: .AVPlayerItemPlaybackStalled,
            object: playerItem
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailedToPlay),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem
        )

        player?.play()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
    }

    @objc private func playerItemStalled(_ notification: Notification) {
        if stallDetectionTime == nil {
            stallDetectionTime = Date()
        }
    }

    @objc private func playerItemFailedToPlay(_ notification: Notification) {
        handlePlaybackFailure()
    }

    @objc private func playerDidFinishPlaying(_ notification: Notification) {
        player?.seek(to: .zero)
        player?.play()
    }

    private func synchronizePlayback() {
        guard let player = player, let playerItem = playerItem else { return }

        let streamStartTime: Date
        if let savedStartTime = defaults.object(forKey: StreamStartTimeKey) as? Date {
            streamStartTime = savedStartTime
        } else {
            let newStartTime = Date()
            defaults.set(newStartTime, forKey: StreamStartTimeKey)
            streamStartTime = newStartTime
        }

        let duration = playerItem.duration
        if duration.isIndefinite || duration.seconds.isNaN || duration.seconds == 0 {
            player.play()
            return
        }

        let elapsedTime = Date().timeIntervalSince(streamStartTime)
        let videoDuration = duration.seconds

        let syncedPosition = elapsedTime.truncatingRemainder(dividingBy: videoDuration)

        player.seek(to: CMTime(seconds: syncedPosition, preferredTimescale: Self.preferredTimescale)) { [weak self] finished in
            if finished {
                self?.player?.play()
            }
        }
    }

    private func handlePlaybackFailure() {
        guard retryCount < maxRetries else {
            return
        }

        retryCount += 1

        if let sourceURL = currentSourceURL {
            let cacheFile = getCacheFilePath(for: sourceURL)
            try? FileManager.default.removeItem(atPath: cacheFile)
        }
        defaults.removeObject(forKey: StreamStartTimeKey)

        let delay = pow(2.0, Double(retryCount - 1))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.retryPlayback()
        }
    }

    private func retryPlayback() {
        player?.pause()
        playerLayer?.removeFromSuperlayer()

        stallDetectionTime = nil

        if let sourceURL = currentSourceURL {
            if let hlsURL = extractHLSURL(sourceURL), let url = URL(string: hlsURL) {
                loadVideo(url: url)
            } else {
                handlePlaybackFailure()
            }
        } else {
            setupScreensaver()
        }
    }

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        rect.fill()
    }

    override func animateOneFrame() {
        if Date().timeIntervalSince(startTime) > 2.0 {
            let idleTime = getSystemIdleTime()
            let screenLocked = isScreenLocked()
            if idleTime < 1.0 && !screenLocked {
                player?.pause()
                player?.replaceCurrentItem(with: nil)
                exit(0)
            }
        }

        playerLayer?.frame = bounds

        guard let player = player, let playerItem = playerItem else { return }

        if let stallTime = stallDetectionTime {
            let stallDuration = Date().timeIntervalSince(stallTime)
            if stallDuration > stallTimeoutSeconds {
                handlePlaybackFailure()
                return
            }
        }

        let isPlaying = player.rate > 0
        let hasError = player.error != nil || playerItem.error != nil

        if hasError {
            handlePlaybackFailure()
            return
        }

        if !isPlaying {
            if stallDetectionTime == nil {
                stallDetectionTime = Date()
            }
            player.play()
        } else {
            stallDetectionTime = nil
        }
    }

    private var configController: ConfigureWindowController?

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        configController = ConfigureWindowController()
        return configController?.window
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        statusObservation?.invalidate()
        player?.pause()
    }
}

class ConfigureWindowController: NSWindowController {

    private let defaults = ScreenSaverDefaults(forModuleWithName: ModuleName)!
    private var urlTextField: NSTextField!
    private var okButton: NSButton!
    private var cancelButton: NSButton!

    override init(window: NSWindow?) {
        let configWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        configWindow.title = "Live Screensaver Configuration"
        configWindow.center()

        super.init(window: configWindow)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let label = NSTextField(labelWithString: "Video URL:")
        label.frame = NSRect(x: 20, y: 90, width: 440, height: 20)
        contentView.addSubview(label)

        urlTextField = NSTextField()
        urlTextField.frame = NSRect(x: 20, y: 60, width: 440, height: 24)
        urlTextField.placeholderString = "Enter YouTube URL or HLS stream URL (.m3u8)"
        urlTextField.stringValue = defaults.string(forKey: URLKey) ?? DefaultURL
        contentView.addSubview(urlTextField)

        let infoLabel = NSTextField(labelWithString: "Supports YouTube URLs (auto-extracted via yt-dlp) or direct HLS streams")
        infoLabel.frame = NSRect(x: 20, y: 35, width: 440, height: 20)
        infoLabel.font = NSFont.systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        contentView.addSubview(infoLabel)

        cancelButton = NSButton(frame: NSRect(x: 270, y: 10, width: 90, height: 28))
        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        contentView.addSubview(cancelButton)

        okButton = NSButton(frame: NSRect(x: 370, y: 10, width: 90, height: 28))
        okButton.title = "OK"
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"
        okButton.target = self
        okButton.action = #selector(okClicked)
        contentView.addSubview(okButton)

        window?.makeFirstResponder(urlTextField)
    }

    @objc private func okClicked() {
        var urlString = urlTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if urlString.isEmpty {
            urlString = DefaultURL
        }

        if URL(string: urlString) != nil {
            defaults.set(urlString, forKey: URLKey)
            defaults.synchronize()
            closeWindow()
        } else {
            showAlert(message: "Please enter a valid URL")
        }
    }

    @objc private func cancelClicked() {
        closeWindow()
    }

    private func closeWindow() {
        if let window = window, let sheetParent = window.sheetParent {
            sheetParent.endSheet(window)
        }
        window?.orderOut(self)
    }

    private func showAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Invalid URL"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let window = window {
            alert.beginSheetModal(for: window)
        }
    }
}
