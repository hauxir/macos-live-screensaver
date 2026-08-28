import Cocoa
import Foundation
import ScreenSaver

// MARK: - Configuration sheet

class ConfigureWindowController: NSWindowController, NSTextFieldDelegate {

    private enum ValidationState {
        case idle
        case validating
        case valid
        case invalid(String)
    }

    private let defaults = ScreenSaverDefaults(forModuleWithName: ModuleName)!
    private var urlTextField: NSTextField!
    private var okButton: NSButton!
    private var cancelButton: NSButton!
    private var statusLabel: NSTextField!  // Shows either error (red) or help text (grey)
    private var spinner: NSProgressIndicator!
    private var trackingArea: NSTrackingArea?
    private let helpText = "Supports stream.place, YouTube (via yt-dlp), or direct HLS streams"

    private var validationState: ValidationState = .idle
    private var validationTimer: Timer?
    private var validationTask: URLSessionDataTask?
    private var ytdlpProcess: Process?
    private var lastValidatedURL: String?
    private let debounceInterval: TimeInterval = 0.2
    private static let ytDlpValidationTimeout: TimeInterval = 20

    override init(window: NSWindow?) {
        let configWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 170),
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
        label.frame = NSRect(x: 20, y: 110, width: 440, height: 20)
        contentView.addSubview(label)

        urlTextField = NSTextField()
        urlTextField.frame = NSRect(x: 20, y: 80, width: 440, height: 24)
        urlTextField.placeholderString = "Enter YouTube, stream.place, or HLS stream URL"
        urlTextField.stringValue = defaults.string(forKey: URLKey) ?? DefaultURL
        contentView.addSubview(urlTextField)

        // Spinner inside text input on the right (x: 20 + 440 - 16 - 6 padding = 438)
        spinner = NSProgressIndicator(frame: NSRect(x: 438, y: 84, width: 16, height: 16))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        contentView.addSubview(spinner)

        // Combined status label - shows help text (grey) or error (red)
        statusLabel = NSTextField(labelWithString: helpText)
        statusLabel.frame = NSRect(x: 20, y: 55, width: 440, height: 20)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        contentView.addSubview(statusLabel)

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
        okButton.isEnabled = false
        contentView.addSubview(okButton)

        // Add tracking area for mouse hover on OK button
        setupOkButtonTracking()

        urlTextField.delegate = self
        window?.makeFirstResponder(urlTextField)

        // Assume existing URL is valid - no need to revalidate on open
        validationState = .valid
        okButton.isEnabled = true
    }

    private func setupOkButtonTracking() {
        guard let contentView = window?.contentView else { return }

        // Create a custom view to track mouse entering the OK button area
        let trackingView = OkButtonTrackingView(frame: okButton.frame)
        trackingView.onMouseEntered = { [weak self] in
            self?.onOkButtonHover()
        }
        contentView.addSubview(trackingView, positioned: .above, relativeTo: okButton)
    }

    private func onOkButtonHover() {
        // If we have a pending timer and haven't validated yet, validate immediately
        if validationTimer != nil {
            validationTimer?.invalidate()
            validationTimer = nil
            performValidation()
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        let urlString = urlTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        // Cancel any pending validation
        cancelPendingValidation()

        // Empty field is always valid (uses default)
        if urlString.isEmpty {
            validationState = .valid
            updateUI()
            return
        }

        // Immediately disable OK and reset to help text while typing
        okButton.isEnabled = false
        statusLabel.stringValue = helpText
        statusLabel.textColor = .secondaryLabelColor

        // Schedule validation after debounce interval
        scheduleValidation()
    }

    private func scheduleValidation() {
        validationTimer?.invalidate()
        validationTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) {
            [weak self] _ in
            self?.performValidation()
        }
    }

    private func cancelPendingValidation() {
        validationTimer?.invalidate()
        validationTimer = nil
        validationTask?.cancel()
        validationTask = nil
        ytdlpProcess?.terminate()
        ytdlpProcess = nil
        spinner?.stopAnimation(nil)
    }

    private func performValidation() {
        guard urlTextField != nil, statusLabel != nil, okButton != nil else { return }

        let urlString = urlTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty field is valid
        if urlString.isEmpty {
            validationState = .valid
            updateUI()
            return
        }

        // Skip if already validated this exact URL
        if urlString == lastValidatedURL, case .valid = validationState {
            return
        }

        // Basic URL format check
        guard let url = URL(string: urlString) else {
            validationState = .invalid("Invalid URL format. Please check for typos.")
            updateUI()
            return
        }

        // http:// was previously accepted here and then blocked at playback time
        // by App Transport Security -- validation showed a green tick for a URL
        // that could never play. Rejecting it up front is the honest answer.
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else {
            if url.scheme?.lowercased() == "http" {
                validationState = .invalid(
                    "macOS blocks plain http:// streams. Use an https:// URL.")
            } else {
                validationState = .invalid("URL must start with https://")
            }
            updateUI()
            return
        }

        guard let host = url.host, !host.isEmpty else {
            validationState = .invalid("URL must include a domain (e.g., youtube.com)")
            updateUI()
            return
        }

        // Start async validation
        validationState = .validating
        updateUI()

        if isStreamPlaceURL(urlString) {
            validateStreamPlaceURL(urlString)
        } else if !needsYtDlpExtraction(urlString) {
            // Direct HLS URL
            validateHLSURL(urlString)
        } else {
            // Needs yt-dlp extraction
            validateWithYtDlp(urlString)
        }
    }

    private func validateStreamPlaceURL(_ urlString: String) {
        guard let hlsURL = getStreamPlaceHLSURL(urlString) else {
            validationState = .invalid("Invalid stream.place URL. Use format: stream.place/username")
            updateUI()
            return
        }
        validateHLSURL(hlsURL.absoluteString)
    }

    private func validateHLSURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            validationState = .invalid("Invalid stream URL")
            updateUI()
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        // Only fetch first 512 bytes to verify accessibility without downloading entire manifest
        request.setValue("bytes=0-511", forHTTPHeaderField: "Range")

        validationTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let error = error as NSError? {
                    if error.code == NSURLErrorCancelled { return }
                    if error.code == NSURLErrorTimedOut {
                        self.validationState = .invalid("Connection timed out. Check your internet or try another URL.")
                    } else if error.code == NSURLErrorCannotFindHost {
                        self.validationState = .invalid("Server not found. Check the URL and try again.")
                    } else if error.code == NSURLErrorNotConnectedToInternet {
                        self.validationState = .invalid("No internet connection. Please check your network.")
                    } else {
                        self.validationState = .invalid("Connection failed: \(error.localizedDescription)")
                    }
                    self.updateUI()
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.validationState = .invalid("Invalid server response. This may not be a valid stream.")
                    self.updateUI()
                    return
                }

                switch httpResponse.statusCode {
                case 200...299:
                    // A 2xx alone is not enough: a captive portal or a site's
                    // custom 404 page answers 200 with HTML. Every HLS playlist
                    // starts with #EXTM3U, and the ranged request above asks for
                    // exactly the bytes that would contain it.
                    let head = String(decoding: data ?? Data(), as: UTF8.self)
                    guard head.contains("#EXTM3U") else {
                        self.validationState = .invalid(
                            "That URL responded, but not with a video stream. Check the link.")
                        self.updateUI()
                        return
                    }
                    self.lastValidatedURL = self.urlTextField.stringValue.trimmingCharacters(
                        in: .whitespacesAndNewlines)
                    self.validationState = .valid
                case 401, 403:
                    self.validationState = .invalid(
                        "Access denied (HTTP \(httpResponse.statusCode)). This stream may require authentication.")
                case 404:
                    self.validationState = .invalid(
                        "Stream not found (HTTP 404). Check the URL or try another stream.")
                case 500...599:
                    self.validationState = .invalid(
                        "Server error (HTTP \(httpResponse.statusCode)). The stream service may be down.")
                default:
                    self.validationState = .invalid(
                        "Unexpected response (HTTP \(httpResponse.statusCode)). Try another URL.")
                }
                self.updateUI()
            }
        }
        validationTask?.resume()
    }

    private func validateWithYtDlp(_ urlString: String) {
        guard let executablePath = findYtDlpPath() else {
            validationState = .invalid(
                ytDlpIsInstalled()
                    ? StreamError.ytDlpUnsafe.reason
                    : "yt-dlp is required for this URL. Install with: brew install yt-dlp")
            updateUI()
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = ["-g", "--no-warnings", urlString]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            DispatchQueue.main.async {
                self?.ytdlpProcess = process
            }

            do {
                try process.run()

                // Without this a hung yt-dlp leaves the sheet spinning forever
                // with OK disabled and no way to tell what went wrong.
                let timeout = DispatchWorkItem {
                    guard process.isRunning else { return }
                    Log.config.error("yt-dlp validation timed out; terminating")
                    process.terminate()
                }
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + Self.ytDlpValidationTimeout, execute: timeout)

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timeout.cancel()
                let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(
                    in: .whitespacesAndNewlines) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(
                    in: .whitespacesAndNewlines) ?? ""

                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.ytdlpProcess = nil

                    if process.terminationStatus == 0, !output.isEmpty {
                        // Successfully extracted URL, now validate it
                        if let firstURL = output.components(separatedBy: .newlines).first,
                            !firstURL.isEmpty
                        {
                            self.validateHLSURL(firstURL)
                        } else {
                            self.validationState = .invalid("Could not extract stream URL")
                            self.updateUI()
                        }
                    } else {
                        // Parse common yt-dlp errors
                        if errorOutput.contains("Video unavailable")
                            || errorOutput.contains("Private video")
                        {
                            self.validationState = .invalid(
                                "Video is unavailable or private. Try another URL.")
                        } else if errorOutput.contains("Sign in") {
                            self.validationState = .invalid(
                                "This video requires sign-in. Try another URL.")
                        } else if errorOutput.contains("not a valid URL")
                            || errorOutput.contains("Unsupported URL")
                        {
                            self.validationState = .invalid(
                                "URL not supported. Try a YouTube or other supported video URL.")
                        } else if errorOutput.contains("HTTP Error 404") {
                            self.validationState = .invalid(
                                "Video not found (404). Check the URL and try again.")
                        } else if errorOutput.contains("Live event will begin") {
                            self.validationState = .invalid(
                                "This is a scheduled live event that hasn't started yet.")
                        } else if errorOutput.contains("is offline") {
                            self.validationState = .invalid(
                                "This stream is currently offline. Try again later or use another URL."
                            )
                        } else if process.terminationReason == .uncaughtSignal {
                            self.validationState = .invalid(
                                "Timed out reading this URL. The site may be slow or blocking us.")
                        } else {
                            self.validationState = .invalid(
                                "Could not load video. Check the URL or try another.")
                        }
                        self.updateUI()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.ytdlpProcess = nil
                    self.validationState = .invalid("Failed to run yt-dlp: \(error.localizedDescription)")
                    self.updateUI()
                }
            }
        }
    }

    private func updateUI() {
        guard urlTextField != nil, statusLabel != nil, okButton != nil, spinner != nil else { return }

        switch validationState {
        case .idle:
            okButton.isEnabled = false
            statusLabel.stringValue = helpText
            statusLabel.textColor = .secondaryLabelColor
            spinner.stopAnimation(nil)

        case .validating:
            okButton.isEnabled = false
            statusLabel.stringValue = helpText
            statusLabel.textColor = .secondaryLabelColor
            spinner.startAnimation(nil)

        case .valid:
            okButton.isEnabled = true
            statusLabel.stringValue = helpText
            statusLabel.textColor = .secondaryLabelColor
            spinner.stopAnimation(nil)

        case .invalid(let message):
            okButton.isEnabled = false
            statusLabel.stringValue = message
            statusLabel.textColor = .systemRed
            spinner.stopAnimation(nil)
        }
    }

    @objc private func okClicked() {
        var urlString = urlTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if urlString.isEmpty {
            urlString = DefaultURL
        }

        Log.config.info("Saved stream URL \(Log.redact(urlString), privacy: .public)")
        defaults.set(urlString, forKey: URLKey)
        defaults.removeObject(forKey: StreamStartTimeKey)  // Reset sync time for new stream
        defaults.synchronize()
        closeWindow()
    }

    @objc private func cancelClicked() {
        cancelPendingValidation()
        closeWindow()
    }

    private func closeWindow() {
        if let window = window, let sheetParent = window.sheetParent {
            sheetParent.endSheet(window)
        }
        window?.orderOut(self)
    }

    deinit {
        cancelPendingValidation()
    }
}

private class OkButtonTrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    // Pass through all clicks to the button underneath
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}
