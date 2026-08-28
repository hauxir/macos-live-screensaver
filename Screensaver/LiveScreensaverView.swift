import AVFoundation
import Cocoa
import Quartz
import ScreenSaver

// MARK: - LiveScreensaverView

@objc(LiveScreensaverView)
class LiveScreensaverView: ScreenSaverView {

    private var playerLayer: AVPlayerLayer?
    private var spinnerLayer: CAShapeLayer?
    private var startTime = Date()

    /// Our own copy of `isPreview`, so `deinit` can consult it without touching
    /// the superclass during deallocation.
    private var isPreviewInstance = false
    /// `exit(0)` skips `deinit`, so the shared player has to be released
    /// explicitly on that path. This guards against releasing it twice.
    private var hasReleasedPlayer = false

    /// The "Unable to stream" notice, and its DVD-logo drift.
    private var noticeLayer: CATextLayer?
    private var noticeOrigin: CGPoint = .zero
    private var noticeVelocity = CGVector(dx: 48, dy: 33)
    private var lastNoticeTick: Date?
    /// Bounds the notice was laid out against, so a resolution change can
    /// trigger a re-wrap rather than leaving it mis-sized or off-screen.
    private var noticeLayoutBounds: CGRect = .zero
    private var displayedError: StreamError?

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

    private func showSpinner() {
        let size: CGFloat = 32
        let lineWidth: CGFloat = 3

        let spinner = CAShapeLayer()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = (size - lineWidth) / 2

        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: size/2, y: size/2), radius: radius,
                    startAngle: 0, endAngle: .pi * 1.5, clockwise: false)

        spinner.path = path
        spinner.fillColor = nil
        spinner.strokeColor = CGColor(gray: 1.0, alpha: 0.8)
        spinner.lineWidth = lineWidth
        spinner.lineCap = .round
        spinner.frame = CGRect(x: center.x - size/2, y: center.y - size/2, width: size, height: size)

        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = CGFloat.pi * 2
        rotation.duration = 1.0
        rotation.repeatCount = .infinity
        spinner.add(rotation, forKey: "spin")

        wantsLayer = true
        layer?.addSublayer(spinner)
        spinnerLayer = spinner
    }

    private func hideSpinner() {
        spinnerLayer?.removeAllAnimations()
        spinnerLayer?.removeFromSuperlayer()
        spinnerLayer = nil
    }

    private func setupScreensaver() {
        animationTimeInterval = 1.0 / 30.0
        wantsLayer = true
        isPreviewInstance = isPreview

        // System Settings instantiates this same class for the small preview
        // thumbnail. That instance must not open a stream -- a second download
        // for a thumbnail nobody is watching -- and must never reach the
        // idle-exit path in animateOneFrame(), which would terminate the process
        // hosting System Settings itself.
        guard !isPreviewInstance else {
            needsDisplay = true
            return
        }

        showSpinner()

        // Listen for player ready notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onSharedPlayerReady),
            name: .sharedPlayerReady,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onSharedPlayerFailed),
            name: .sharedPlayerFailed,
            object: nil
        )

        // Register with the shared player manager
        let manager = SharedPlayerManager.shared
        manager.registerView()

        // If player is already ready (another view already set it up), attach immediately
        if manager.player != nil {
            attachPlayerLayer()
        } else if let error = manager.currentError {
            // A second display attached after playback had already given up.
            showErrorNotice(error)
        }
    }

    /// Called by SharedPlayerManager when the player becomes ready
    @objc private func onSharedPlayerReady() {
        hideErrorNotice()
        attachPlayerLayer()
    }

    /// Called by SharedPlayerManager when playback has given up.
    @objc private func onSharedPlayerFailed() {
        guard let error = SharedPlayerManager.shared.currentError else { return }
        showErrorNotice(error)
    }

    // MARK: - Error notice

    /// Builds the notice: "Unable to stream" in bold, the reason underneath in
    /// regular weight, wrapped so the block sits close to 16:9.
    private func noticeText(for error: StreamError) -> NSAttributedString {
        let titleSize = max(16, bounds.height / 26)
        let bodySize = titleSize * 0.62

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping

        let text = NSMutableAttributedString(
            string: "Unable to stream\n",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: titleSize),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
            ]
        )
        text.append(
            NSAttributedString(
                string: error.reason,
                attributes: [
                    .font: NSFont.systemFont(ofSize: bodySize),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.75),
                    .paragraphStyle: paragraph,
                ]
            )
        )
        return text
    }

    /// Finds the wrap width whose resulting text block is closest to 16:9.
    ///
    /// Height falls as width grows (the same words wrap into fewer lines), so
    /// the height-to-width ratio decreases monotonically and can be searched.
    private func noticeSize(for text: NSAttributedString) -> CGSize {
        func height(atWidth width: CGFloat) -> CGFloat {
            ceil(
                text.boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                ).height)
        }

        var narrow = max(160, bounds.width * 0.15)
        var wide = max(narrow + 1, bounds.width * 0.6)
        let target: CGFloat = 9.0 / 16.0

        for _ in 0..<14 {
            let mid = (narrow + wide) / 2
            if height(atWidth: mid) / mid > target {
                narrow = mid
            } else {
                wide = mid
            }
        }
        return CGSize(width: ceil(wide), height: height(atWidth: wide))
    }

    private func showErrorNotice(_ error: StreamError) {
        guard !isPreviewInstance, bounds.width > 0, bounds.height > 0 else { return }

        hideSpinner()
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        noticeLayer?.removeFromSuperlayer()

        let text = noticeText(for: error)
        let size = noticeSize(for: text)

        let notice = CATextLayer()
        notice.string = text
        notice.isWrapped = true
        notice.alignmentMode = .center
        notice.contentsScale = window?.backingScaleFactor ?? 2
        notice.bounds = CGRect(origin: .zero, size: size)
        notice.anchorPoint = .zero

        // Start somewhere off-centre so multiple displays are not in lockstep.
        noticeOrigin = CGPoint(
            x: (bounds.width - size.width) * CGFloat.random(in: 0.15...0.85),
            y: (bounds.height - size.height) * CGFloat.random(in: 0.15...0.85)
        )
        notice.position = noticeOrigin
        lastNoticeTick = nil

        wantsLayer = true
        layer?.addSublayer(notice)
        noticeLayer = notice
        noticeLayoutBounds = bounds
        displayedError = error
    }

    private func hideErrorNotice() {
        noticeLayer?.removeFromSuperlayer()
        noticeLayer = nil
        lastNoticeTick = nil
        displayedError = nil
        noticeLayoutBounds = .zero
    }

    /// Drifts the notice across the screen, reflecting off the edges. Keeps the
    /// text moving so it cannot burn in, and makes it obvious the machine is
    /// alive rather than hung.
    private func advanceErrorNotice() {
        guard let notice = noticeLayer else { return }

        // Display reconfigured (resolution change, or the saver moved between
        // screens): re-wrap against the new bounds.
        if bounds != noticeLayoutBounds, let error = displayedError {
            showErrorNotice(error)
            return
        }

        let now = Date()
        defer { lastNoticeTick = now }
        guard let last = lastNoticeTick else { return }
        // Cap the step so a stalled frame cannot teleport the notice.
        let elapsed = min(now.timeIntervalSince(last), 0.1)
        guard elapsed > 0 else { return }

        let size = notice.bounds.size
        let maxX = max(0, bounds.width - size.width)
        let maxY = max(0, bounds.height - size.height)

        noticeOrigin.x += noticeVelocity.dx * elapsed
        noticeOrigin.y += noticeVelocity.dy * elapsed

        if noticeOrigin.x <= 0 {
            noticeOrigin.x = 0
            noticeVelocity.dx = abs(noticeVelocity.dx)
        } else if noticeOrigin.x >= maxX {
            noticeOrigin.x = maxX
            noticeVelocity.dx = -abs(noticeVelocity.dx)
        }

        if noticeOrigin.y <= 0 {
            noticeOrigin.y = 0
            noticeVelocity.dy = abs(noticeVelocity.dy)
        } else if noticeOrigin.y >= maxY {
            noticeOrigin.y = maxY
            noticeVelocity.dy = -abs(noticeVelocity.dy)
        }

        // Implicit layer animations would smear a per-frame move; the drift is
        // already continuous.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        notice.position = noticeOrigin
        CATransaction.commit()
    }

    private func attachPlayerLayer() {
        guard let player = SharedPlayerManager.shared.player else {
            return
        }

        // Remove old layer if exists
        playerLayer?.removeFromSuperlayer()

        hideSpinner()

        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.frame = bounds
        playerLayer?.videoGravity = .resizeAspectFill

        if let pLayer = playerLayer, let selfLayer = self.layer {
            selfLayer.addSublayer(pLayer)
        }
    }

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        rect.fill()

        if isPreviewInstance {
            drawPreviewPlaceholder()
        }
    }

    /// A static stand-in for the System Settings preview: no network, no
    /// animation, just enough to show which stream is configured.
    private func drawPreviewPlaceholder() {
        let configured =
            ScreenSaverDefaults(forModuleWithName: ModuleName)?.string(forKey: URLKey) ?? DefaultURL
        let label = URL(string: configured)?.host ?? "Live Screensaver"

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(8, bounds.height / 12)),
            .foregroundColor: NSColor.white.withAlphaComponent(0.6),
        ]
        let attributed = NSAttributedString(string: label, attributes: attributes)
        let size = attributed.size()
        attributed.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }

    override func animateOneFrame() {
        // The preview has no player, no stream and no business quitting anything.
        guard !isPreviewInstance else { return }

        if Date().timeIntervalSince(startTime) > 2.0 {
            let idleTime = getSystemIdleTime()
            let screenLocked = isScreenLocked()
            if idleTime < 1.0 && !screenLocked {
                stopOnUserActivity()
            }
        }

        playerLayer?.frame = bounds
        advanceErrorNotice()

        // Let the shared manager handle stall detection and recovery
        SharedPlayerManager.shared.checkStall()
    }

    /// Ends the screensaver when the user comes back.
    ///
    /// `exit(0)` terminates the host process rather than just this view, and
    /// skips `deinit` on the way out, so the shared player is released
    /// explicitly first. Reached only on a real screensaver instance -- never in
    /// preview, where it would take System Settings down with it.
    private func stopOnUserActivity() {
        stopAnimation()
        releasePlayer()
        exit(0)
    }

    private func releasePlayer() {
        guard !isPreviewInstance, !hasReleasedPlayer else { return }
        hasReleasedPlayer = true
        SharedPlayerManager.shared.unregisterView()
    }

    private var configController: ConfigureWindowController?

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        configController = ConfigureWindowController()
        return configController?.window
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        playerLayer?.removeFromSuperlayer()
        releasePlayer()
    }
}
