import AVFoundation
import Cocoa
import CryptoKit
import Foundation
import ScreenSaver

// MARK: - Shared Player Manager (singleton for multi-monitor support)

extension Notification.Name {
    static let sharedPlayerReady = Notification.Name("SharedPlayerReadyNotification")
    static let sharedPlayerFailed = Notification.Name("SharedPlayerFailedNotification")
}

/// Why playback could not start or continue, in terms a user can act on.
///
/// The configuration sheet already explains failures well while a URL is being
/// typed. These are the same class of problem discovered later -- a stream that
/// ends overnight, or a yt-dlp that gets uninstalled -- where the only place to

class SharedPlayerManager {
    static let shared = SharedPlayerManager()

    private(set) var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var statusObservation: NSKeyValueObservation?
    private var viewCount = 0
    private var isSettingUp = false
    private var currentSourceURL: String?
    private var retryCount = 0
    /// True between scheduling a retry and that retry resolving. Without it,
    /// `checkStall()` -- which runs on every animation frame of every view --
    /// re-enters the failure path before the previous retry has had a chance.
    private var isRetryScheduled = false
    /// Set once the retry budget is spent, so the manager stops churning.
    private(set) var hasFailedPermanently = false
    private var lastStallCheck = Date.distantPast
    /// What to report if the retries run out; set by whichever step failed.
    private var failureHint: StreamError?
    /// Non-nil once playback has given up. Views render this.
    private(set) var currentError: StreamError?

    private let defaults = ScreenSaverDefaults(forModuleWithName: ModuleName)!
    private let cacheExpirationSeconds: TimeInterval = 300
    private let extractionTimeoutSeconds: TimeInterval = 15
    private let maxRetries = 3
    private let stallTimeoutSeconds: TimeInterval = 10
    /// `checkStall()` is called at the animation frame rate by every view. The
    /// work it does only needs to happen about once a second.
    private let stallCheckInterval: TimeInterval = 1
    private var stallDetectionTime: Date?

    /// ScreenSaverDefaults needs an explicit synchronize for writes to persist.
    /// The configuration sheet did this; the playback paths did not, so the
    /// stream start time could silently fail to be written -- taking
    /// multi-display sync and the retry reset with it.
    private func writeDefault(_ value: Any?, forKey key: String) {
        if let value = value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
    }
    private static let preferredTimescale: CMTimeScale = 600

    private init() {}

    // MARK: - Threading contract
    //
    // Every property of this class is read and written on the main queue only.
    // The blocking work -- yt-dlp, and the cache and lock files it touches --
    // runs on background queues, but those blocks operate on locals and hop back
    // to main before touching any state here.
    //
    // registerView/unregisterView are the two entry points that can arrive from
    // elsewhere (a view's deinit is not guaranteed to be on the main thread), so
    // they bounce themselves onto it.

    func registerView() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.registerView() }
            return
        }
        viewCount += 1
        Log.player.debug("View registered (\(self.viewCount) attached)")
        if viewCount == 1 && player == nil && !isSettingUp {
            setupPlayer()
        }
    }

    func unregisterView() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.unregisterView() }
            return
        }
        viewCount -= 1
        Log.player.debug("View unregistered (\(self.viewCount) attached)")
        if viewCount <= 0 {
            cleanup()
        }
    }

    private func notifyViewsPlayerReady() {
        NotificationCenter.default.post(name: .sharedPlayerReady, object: self)
    }

    /// Give up and tell the views why, so the user sees something other than a
    /// black screen.
    private func failPermanently(with error: StreamError) {
        Log.player.error("Giving up: \(error.reason, privacy: .public)")
        hasFailedPermanently = true
        isSettingUp = false
        isRetryScheduled = false
        stallDetectionTime = nil
        currentError = error
        player?.pause()
        NotificationCenter.default.post(name: .sharedPlayerFailed, object: self)
    }

    private func setupPlayer() {
        guard !isSettingUp else {
            return
        }
        isSettingUp = true
        failureHint = nil

        let originalURLString = defaults.string(forKey: URLKey) ?? DefaultURL
        Log.player.info("Setting up player for \(Log.redact(originalURLString), privacy: .public)")

        if isStreamPlaceURL(originalURLString) {
            guard let hlsURL = getStreamPlaceHLSURL(originalURLString) else {
                // Previously returned with isSettingUp still true, permanently
                // wedging the manager: no view could ever trigger setup again.
                failPermanently(with: .invalidConfiguredURL)
                return
            }
            loadVideo(url: hlsURL)
            return
        }

        var urlString = originalURLString

        if needsYtDlpExtraction(originalURLString) {
            // Retrying will not conjure up a missing binary, so say so straight
            // away rather than spending the retry budget first.
            guard let ytDlp = findYtDlpPath() else {
                if ytDlpIsInstalled() {
                    failPermanently(with: .ytDlpUnsafe)
                } else {
                    Log.extraction.error("yt-dlp not found in any known location")
                    failPermanently(with: .ytDlpMissing)
                }
                return
            }
            Log.extraction.info(
                "Using yt-dlp \(ytdlpVersion, privacy: .public) at \(ytDlp, privacy: .public)")
            currentSourceURL = originalURLString

            if let cachedURL = getCachedHLSURL(for: originalURLString) {
                Log.extraction.info("Cache hit; refreshing in the background")
                urlString = cachedURL

                DispatchQueue.global(qos: .background).async { [weak self] in
                    _ = self?.extractHLSURL(originalURLString, forceRefresh: true)
                }
            } else {
                Log.extraction.info("Cache miss; extracting synchronously")
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let extracted = self?.extractHLSURL(originalURLString)
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        // Extraction can fail because yt-dlp is missing, the
                        // lock is held, or the network is down. Previously this
                        // block simply did nothing, leaving isSettingUp true
                        // forever and the user on an endless spinner.
                        guard let extracted = extracted, let url = URL(string: extracted) else {
                            self.isSettingUp = false
                            self.failureHint = .extractionFailed
                            self.handlePlaybackFailure()
                            return
                        }
                        self.loadVideo(url: url)
                    }
                }
                return
            }
        }

        guard let url = URL(string: urlString) else {
            failPermanently(with: .invalidConfiguredURL)
            return
        }

        loadVideo(url: url)
    }

    private func loadVideo(url: URL) {
        NotificationCenter.default.removeObserver(self)
        statusObservation?.invalidate()

        playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        player?.volume = 0.0
        player?.automaticallyWaitsToMinimizeStalling = false

        statusObservation = playerItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                if item.status == .readyToPlay {
                    self?.synchronizePlayback()
                    self?.stallDetectionTime = nil
                    self?.retryCount = 0
                    self?.isRetryScheduled = false
                    self?.hasFailedPermanently = false
                    self?.isSettingUp = false
                    self?.failureHint = nil
                    self?.currentError = nil
                    Log.player.info("Player ready")
                    self?.notifyViewsPlayerReady()
                } else if item.status == .failed {
                    if self?.failureHint == nil {
                        self?.failureHint =
                            (item.error as NSError?)?.code == NSURLErrorNotConnectedToInternet
                            ? .noNetwork : .streamUnavailable
                    }
                    self?.handlePlaybackFailure()
                }
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        player?.play()
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
        // Restart through the same synchronisation used on first load. A plain
        // seek to zero ignored StreamStartTime, so displays that were aligned
        // when playback started drifted apart after the first loop.
        synchronizePlayback()
    }

    private func synchronizePlayback() {
        guard let player = player, let playerItem = playerItem else { return }

        let streamStartTime: Date
        if let savedStartTime = defaults.object(forKey: StreamStartTimeKey) as? Date {
            streamStartTime = savedStartTime
        } else {
            let newStartTime = Date()
            writeDefault(newStartTime, forKey: StreamStartTimeKey)
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

        player.seek(
            to: CMTime(seconds: syncedPosition, preferredTimescale: Self.preferredTimescale)
        ) { [weak self] finished in
            if finished {
                self?.player?.play()
            }
        }
    }

    private func handlePlaybackFailure() {
        // Re-entry guard. This is reachable from checkStall(), which every view
        // calls on every animation frame; without it a single expired stall
        // spends the entire retry budget within a few frames and the
        // exponential backoff below never actually delays anything.
        guard !isRetryScheduled, !hasFailedPermanently else { return }

        // Clearing this is what stops the next frame seeing the same expired
        // stall and calling straight back in.
        stallDetectionTime = nil

        guard retryCount < maxRetries else {
            failPermanently(with: failureHint ?? .retriesExhausted)
            return
        }

        retryCount += 1
        isRetryScheduled = true
        Log.player.notice(
            "Playback failed; retry \(self.retryCount)/\(self.maxRetries) in \(pow(2.0, Double(self.retryCount - 1)))s"
        )

        if let sourceURL = currentSourceURL {
            let cacheFile = getCacheFilePath(for: sourceURL)
            try? FileManager.default.removeItem(atPath: cacheFile)
        }
        writeDefault(nil, forKey: StreamStartTimeKey)

        let delay = pow(2.0, Double(retryCount - 1))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.retryPlayback()
        }
    }

    private func retryPlayback() {
        player?.pause()
        stallDetectionTime = nil

        guard let sourceURL = currentSourceURL else {
            // A direct HLS URL needs no extraction; rebuild from defaults.
            isRetryScheduled = false
            isSettingUp = false
            setupPlayer()
            return
        }

        // extractHLSURL() runs yt-dlp with waitUntilExit(). On the main queue
        // that freezes the screensaver, and the process hosting it, for however
        // long yt-dlp takes -- typically seconds. The initial setup path already
        // dispatches this off the main queue; this one did not.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let extracted = self?.extractHLSURL(sourceURL)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRetryScheduled = false
                guard let extracted = extracted, let url = URL(string: extracted) else {
                    self.handlePlaybackFailure()
                    return
                }
                self.loadVideo(url: url)
            }
        }
    }

    func checkStall() {
        // Called from animateOneFrame(), so this runs at the frame rate for
        // every connected display. Throttle to roughly once a second.
        let now = Date()
        guard now.timeIntervalSince(lastStallCheck) >= stallCheckInterval else { return }
        lastStallCheck = now

        // Nothing to police while setup or a retry is in flight, or once the
        // retry budget is spent.
        guard !hasFailedPermanently, !isRetryScheduled, !isSettingUp else { return }

        if let stallTime = stallDetectionTime,
            now.timeIntervalSince(stallTime) > stallTimeoutSeconds
        {
            handlePlaybackFailure()
            return
        }

        if player?.error != nil || playerItem?.error != nil {
            handlePlaybackFailure()
            return
        }

        if (player?.rate ?? 0) > 0 {
            stallDetectionTime = nil
        } else {
            if stallDetectionTime == nil {
                stallDetectionTime = now
            }
            player?.play()
        }
    }

    private func cleanup() {
        NotificationCenter.default.removeObserver(self)
        statusObservation?.invalidate()
        player?.pause()
        player = nil
        playerItem = nil
        isSettingUp = false
        retryCount = 0
        isRetryScheduled = false
        hasFailedPermanently = false
        stallDetectionTime = nil
        lastStallCheck = .distantPast
        failureHint = nil
        currentError = nil
        viewCount = 0
    }

    // MARK: - URL Extraction helpers

    private func md5Hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }

    private func getCacheFilePath(for url: String) -> String {
        let hash = md5Hash(url)
        return (NSTemporaryDirectory() as NSString).appendingPathComponent("screensaver_\(hash)")
    }


    private func getCachedHLSURL(for sourceURL: String) -> String? {
        let cacheFile = getCacheFilePath(for: sourceURL)

        guard
            let cachedURL = try? String(contentsOfFile: cacheFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            let attributes = try? FileManager.default.attributesOfItem(atPath: cacheFile),
            let modifiedAt = attributes[.modificationDate] as? Date
        else {
            return nil
        }

        guard
            HLSCachePolicy.isFresh(
                cachedURL: cachedURL,
                modifiedAt: modifiedAt,
                maxAge: cacheExpirationSeconds)
        else {
            try? FileManager.default.removeItem(atPath: cacheFile)
            return nil
        }

        return cachedURL
    }

    private func cacheHLSURL(_ url: String, for sourceURL: String) {
        let cacheFile = getCacheFilePath(for: sourceURL)
        do {
            try url.write(toFile: cacheFile, atomically: true, encoding: .utf8)
        } catch {
            Log.extraction.error("Failed to cache extracted URL: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func getExtractionLockPath(for url: String) -> String {
        let hash = md5Hash(url)
        return (NSTemporaryDirectory() as NSString).appendingPathComponent(
            "screensaver_\(hash)_lock")
    }

    /// Takes the extraction lock, or reports that someone else holds it.
    ///
    /// `O_CREAT | O_EXCL` creates the file only if it does not already exist,
    /// and the kernel makes that test-and-create atomic. The previous
    /// check-then-create left a window in which two processes could both decide
    /// the lock was free and both spawn yt-dlp.
    private func acquireExtractionLock(at path: String) -> Bool {
        let descriptor = open(path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    /// Removes a lock left behind by an extraction that crashed or was killed.
    private func clearStaleExtractionLock(at path: String) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
            let lockTimestamp = attributes[.modificationDate] as? Date,
            Date().timeIntervalSince(lockTimestamp) >= extractionTimeoutSeconds
        else {
            return
        }
        Log.extraction.notice("Clearing stale extraction lock")
        try? FileManager.default.removeItem(atPath: path)
    }

    private func extractHLSURL(_ sourceURL: String, forceRefresh: Bool = false) -> String? {
        if !forceRefresh, let cachedURL = getCachedHLSURL(for: sourceURL) {
            return cachedURL
        }

        let lockFile = getExtractionLockPath(for: sourceURL)
        clearStaleExtractionLock(at: lockFile)

        guard acquireExtractionLock(at: lockFile) else {
            Log.extraction.debug("Extraction already in progress for this URL; skipping")
            return nil
        }
        // One release point for every exit path below, including the throwing
        // ones. The old code released it in two places and missed a third.
        defer { try? FileManager.default.removeItem(atPath: lockFile) }

        guard let executablePath = findYtDlpPath() else {
            return nil
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = ["-g", sourceURL]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        var extractedURL: String?
        let startedAt = Date()

        do {
            try task.run()

            // Process has no timeout of its own, and yt-dlp will sit there
            // indefinitely against a stalled network. extractionTimeoutSeconds
            // previously governed only how long a lock file was considered
            // fresh -- nothing bounded the process itself.
            let timeout = DispatchWorkItem {
                guard task.isRunning else { return }
                Log.extraction.error(
                    "yt-dlp exceeded \(self.extractionTimeoutSeconds, privacy: .public)s; terminating")
                task.terminate()
            }
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + extractionTimeoutSeconds, execute: timeout)

            // Close the parent's copy of the write end, then drain before
            // waiting: a child that fills the pipe buffer blocks until someone
            // reads it, so waiting first can deadlock.
            try? pipe.fileHandleForWriting.close()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            timeout.cancel()

            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines),
                !output.isEmpty,
                let firstURL = output.components(separatedBy: .newlines).first
            {
                cacheHLSURL(firstURL, for: sourceURL)
                extractedURL = firstURL
            }

            let elapsed = Date().timeIntervalSince(startedAt)
            if extractedURL != nil {
                Log.extraction.info(
                    "Extracted stream URL in \(String(format: "%.1f", elapsed), privacy: .public)s")
            } else {
                Log.extraction.error(
                    "yt-dlp exited \(task.terminationStatus) with no URL after \(String(format: "%.1f", elapsed), privacy: .public)s"
                )
            }
        } catch {
            Log.extraction.error("yt-dlp failed to launch: \(error.localizedDescription, privacy: .public)")
        }

        return extractedURL
    }
}
