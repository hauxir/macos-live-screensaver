---
# SAVE-xncv
title: Screensaver kills the System Settings preview with exit(0)
status: completed
type: bug
priority: critical
created_at: 2026-08-26T07:08:01Z
updated_at: 2026-08-26T07:19:14Z
parent: SAVE-5ucd
---

`animateOneFrame()` calls `exit(0)` when it detects user activity:

```swift
override func animateOneFrame() {
    if Date().timeIntervalSince(startTime) > 2.0 {
        let idleTime = getSystemIdleTime()
        let screenLocked = isScreenLocked()
        if idleTime < 1.0 && !screenLocked {
            exit(0)
        }
    }
    ...
}
```

Two problems, one of which is almost certainly a bug users are hitting today.

## 1. The preview instance runs this code

`init(frame:isPreview:)` stores nothing about `isPreview`, and none of the playback or idle-detection logic checks it. The same view runs inside the small preview thumbnail in System Settings → Screen Saver — where the user is, by definition, moving the mouse.

Two seconds after the preview appears, `idleTime < 1.0` is true and the view calls `exit(0)`, killing the process that hosts the settings preview (`legacyScreenSaver.appex`).

This matches the symptom already documented in the README:

> **Note**: macOS screensaver UI can be buggy. If the Options button is unresponsive, try closing and reopening System Settings. PRs welcome for anyone who can figure out why.

This bean is that PR.

## 2. `exit(0)` is the wrong tool regardless

On modern macOS the saver is loaded into a shared host process. Calling `exit()` terminates the host, not just this view — it skips `deinit`, so `unregisterView()` never runs and the shared `AVPlayer` is never torn down cleanly.

## Fix

- Store `isPreview` and gate both the idle-exit check and network playback behind it. The preview should render something cheap and static rather than opening a live stream (a second stream for a thumbnail nobody is watching is also a waste of bandwidth).
- Replace `exit(0)` with a clean stop path; keep `exit(0)` only as a last resort on the real screensaver instance, never in preview.

## Tasks

- [x] Store `isPreview` from the initialiser
- [x] Skip idle-detection / exit entirely when `isPreview` is true
- [x] Skip live playback in preview; render a static placeholder instead
- [x] Verify the Options button stays responsive in System Settings

## Summary of Changes

`LiveScreensaverView` now knows whether it is the real screensaver or the System Settings preview, and behaves accordingly.

- `isPreviewInstance` captures `isPreview` at setup, so `deinit` can consult it without touching the superclass mid-deallocation.
- `setupScreensaver()` returns early in preview: no spinner, no notification observer, no `registerView()`, and therefore no stream.
- `animateOneFrame()` returns immediately in preview, so the idle check can never run there.
- The preview draws a static placeholder instead — the configured stream's host, centred and dimmed. No network, no animation, and it tells the user which stream is set up.
- `exit(0)` moved into `stopOnUserActivity()`, which calls `stopAnimation()` and releases the shared player first. `exit()` skips `deinit`, so without this the `AVPlayer` was never torn down.
- `releasePlayer()` is guarded by `hasReleasedPlayer` so the `exit` path and `deinit` cannot both decrement the view count.

The README note describing the Options button as an unexplained macOS bug has been rewritten, since this was the cause.

## Why this was the bug

The preview thumbnail in System Settings instantiates the same class. Nothing checked `isPreview`, so two seconds after the preview appeared, `idleTime < 1.0` was trivially true — the user is moving the mouse, that is why the settings pane is open — and the view called `exit(0)`, terminating `legacyScreenSaver.appex`, the process hosting the preview *and* the Options sheet.

## Follow-up: exit(0) is still there

- [ ] Replace `exit(0)` with a clean stop that lets the engine tear the saver down

Kept deliberately. The manual idle-detection and exit were presumably added because the screensaver was not stopping on its own in the author's setup, and removing that without a macOS machine to test on risks trading a fixed bug for a screensaver that will not dismiss. The dangerous half — running it in preview — is fixed here; the remaining cleanup is safe to do later, with a way to test it.
