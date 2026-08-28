---
# SAVE-9ndi
title: Retry, stall and setup state machine defects
status: completed
type: bug
priority: high
created_at: 2026-08-26T07:08:01Z
updated_at: 2026-08-26T07:21:07Z
parent: SAVE-5ucd
---

Three defects in `SharedPlayerManager`'s retry path. Together they turn a recoverable stream hiccup into a permanent black screen.

## 1. Exponential backoff never happens — all retries burn in ~3 frames

`checkStall()` is called from `animateOneFrame()`, i.e. **30 times per second**. When a stall exceeds the timeout it calls `handlePlaybackFailure()`:

```swift
func checkStall() {
    if let stallTime = stallDetectionTime {
        let stallDuration = Date().timeIntervalSince(stallTime)
        if stallDuration > stallTimeoutSeconds {
            handlePlaybackFailure()   // <-- stallDetectionTime is never cleared
            return
        }
    }
```

`handlePlaybackFailure()` does not reset `stallDetectionTime`, so the *next frame* — 33 ms later — sees the same expired stall and fires again. `retryCount` reaches `maxRetries` within about three frames, and the carefully written `pow(2.0, ...)` backoff delays all fire at once against a stream that has had no time to recover.

With multiple monitors it is worse: every view calls `checkStall()` on every frame, so N views multiply the rate.

## 2. `retryPlayback()` blocks the main thread on yt-dlp

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
    self?.retryPlayback()      // calls extractHLSURL -> task.waitUntilExit()
}
```

`extractHLSURL` runs `yt-dlp` synchronously with `waitUntilExit()`. On the main queue that freezes the screensaver — and the whole host process — for however long yt-dlp takes, typically several seconds and up to the 15 s extraction timeout.

The initial setup path already gets this right by dispatching to a background queue; the retry path does not.

## 3. Two paths wedge the player permanently behind `isSettingUp`

`setupPlayer()` sets `isSettingUp = true` on entry, and `registerView()` only starts setup when `!isSettingUp`. Two early returns never clear the flag:

- **stream.place URL that fails to parse** — `getStreamPlaceHLSURL` returns nil, the `if` body falls through, and the function returns with the flag still set.
- **initial yt-dlp extraction returns nil** — lock file held by another process, yt-dlp not installed, or network down. The background block simply does nothing and returns.

In both cases `isSettingUp` stays `true` forever. No view can ever trigger setup again, and the user is left with the loading spinner until the machine sleeps.

## Also in scope

`checkStall()` calls `player?.play()` on every frame while paused, which is a wasteful no-op at 30 Hz.

## Tasks

- [x] Clear `stallDetectionTime` in `handlePlaybackFailure()` and guard re-entry while a retry is scheduled
- [x] Move `retryPlayback()`'s yt-dlp call off the main queue
- [x] Ensure every exit path from `setupPlayer()` clears `isSettingUp`
- [x] Add a `failed` terminal state so exhausting retries is explicit rather than implicit
- [x] Rate-limit `checkStall()` so it does real work at most ~1 Hz, not 30 Hz per view

## Summary of Changes

### Backoff now actually backs off

`handlePlaybackFailure()` gained a re-entry guard (`isRetryScheduled`, `hasFailedPermanently`) and now clears `stallDetectionTime` on entry. Previously it did neither, so the next animation frame — 33 ms later — saw the same expired stall and called straight back in. The retry budget was spent in about three frames and every `pow(2.0, ...)` delay fired at once against a stream that had been given no time to recover.

### yt-dlp no longer runs on the main thread

`retryPlayback()` dispatches `extractHLSURL()` to a background queue and hops back to main to load the result. It was calling it directly from a main-queue `asyncAfter`, and `extractHLSURL` uses `waitUntilExit()` — freezing the screensaver and its host process for however long yt-dlp took.

### The two permanent wedges are closed

Both paths that returned from `setupPlayer()` with `isSettingUp` still `true` — an unparseable stream.place URL, and an initial extraction returning nil — now clear the flag. Because `registerView()` only starts setup when `!isSettingUp`, either one previously meant no view could ever trigger setup again and the user sat on the spinner until the machine slept.

### Terminal failure is explicit

`hasFailedPermanently` is set when the retry budget is spent, and cleared on a successful `readyToPlay`. This stops the manager churning after giving up, and gives the error-notice bean a state to render.

### checkStall() throttled

It was doing real work — and calling `player?.play()` — 30 times a second per view, so N monitors multiplied the rate. Now throttled to once a second, and it returns early while setup or a retry is in flight rather than fighting them.

## Not verified by execution

No Swift toolchain available here, so this is reasoned from the source rather than run. The state machine is the part of this codebase most worth a careful read in review; the intended invariant is that `isSettingUp`, `isRetryScheduled` and `hasFailedPermanently` are each cleared on exactly one success path (`readyToPlay`) and on `cleanup()`.
