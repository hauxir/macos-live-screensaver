---
# SAVE-rj01
title: Concurrency, defaults persistence and loop-sync hardening
status: completed
type: bug
priority: normal
created_at: 2026-08-26T07:08:35Z
updated_at: 2026-08-26T07:27:35Z
parent: SAVE-5ucd
---

A collection of smaller correctness issues in `SharedPlayerManager`, none fatal alone but all capable of producing confusing behaviour.

## 1. `ScreenSaverDefaults` writes without `synchronize()`

`synchronizePlayback()` and `handlePlaybackFailure()` both mutate defaults:

```swift
defaults.set(newStartTime, forKey: StreamStartTimeKey)
defaults.removeObject(forKey: StreamStartTimeKey)
```

Neither calls `synchronize()`. `ScreenSaverDefaults` requires an explicit synchronise for writes to persist — the config sheet's `okClicked()` gets this right, these two do not. The stream start time can silently fail to persist, so multi-monitor sync and the retry reset both misbehave.

## 2. Looped playback drifts out of sync between monitors

`playerDidFinishPlaying` restarts a finished item with a plain seek to zero:

```swift
player?.seek(to: .zero)
player?.play()
```

This bypasses `synchronizePlayback()`, so the position-from-`StreamStartTime` calculation that keeps displays aligned is applied only on the *first* load. After one loop, the sync is gone.

## 3. The extraction lock is check-then-create, not atomic

```swift
if FileManager.default.fileExists(atPath: lockFile) { ... }
try "".write(toFile: lockFile, atomically: true, encoding: .utf8)
```

Two processes can both pass the existence check and both spawn `yt-dlp`. Use `O_CREAT|O_EXCL` (`open` with exclusive create) so the lock is acquired atomically. The lock is also not released if `findYtDlpPath()` fails after it is taken — that path does remove it, but the ordering is fragile and worth restructuring with `defer`.

## 4. Shared mutable state crosses queues without synchronisation

`isSettingUp`, `retryCount`, `viewCount`, `currentSourceURL` and `stallDetectionTime` are read and written from the main queue (`checkStall`, KVO callbacks, `registerView`) *and* from background queues (the extraction blocks in `setupPlayer`). There is no lock or queue confinement, so these are data races.

`registerView()`/`unregisterView()` are also called from view lifecycle on the main thread while `viewCount` is decremented in `deinit`, which is not guaranteed to be on the main thread.

Confine all manager state to a single serial queue, or make the whole manager `@MainActor` and hop explicitly for the blocking work.

## Tasks

- [x] Add `synchronize()` after every defaults write, or centralise writes in one helper
- [x] Route loop restarts through `synchronizePlayback()`
- [x] Make the extraction lock atomic with `O_CREAT|O_EXCL` and release it with `defer`
- [x] Confine manager state to one queue / actor and document the threading contract
- [x] Audit `deinit` for main-thread assumptions

## Summary of Changes

### Defaults writes now persist

`ScreenSaverDefaults` requires an explicit `synchronize()` for writes to stick. The configuration sheet did this; `synchronizePlayback()` and `handlePlaybackFailure()` did not. A new `writeDefault(_:forKey:)` helper wraps set/remove plus synchronise, and both call sites use it. The stream start time could previously fail to be written, taking multi-display alignment and the retry reset with it.

### Looping keeps displays in sync

`playerDidFinishPlaying` now calls `synchronizePlayback()` rather than seeking to zero and playing. The old restart ignored `StreamStartTime`, so displays that were aligned when playback began drifted apart after the first loop — the sync was only ever applied once.

### The extraction lock is atomic

`acquireExtractionLock(at:)` uses `open(path, O_CREAT | O_EXCL | O_WRONLY)`. The kernel makes that test-and-create atomic, closing the window in which two processes could both find the lock absent and both spawn yt-dlp.

Stale-lock clearing moved into `clearStaleExtractionLock(at:)`, and release moved to a single `defer` immediately after acquisition. The old code released the lock in two places and missed a third — the `findYtDlpPath()` failure path released it, but a throw between the two release points would have left it behind until it aged out.

### Threading contract, stated and enforced at the edges

The class-level comment now states the invariant: every property is read and written on the main queue only; background work operates on locals and hops back before touching state.

`registerView()` and `unregisterView()` are the two entry points that can arrive from elsewhere — a view's `deinit` is not guaranteed to run on the main thread — so they bounce themselves onto it.

## On the wider concurrency question

The audit found the situation better than the bean assumed. After the retry-path fix in SAVE-9ndi, `extractHLSURL` is only ever called from background queues and touches no manager state — only the file system, a `let` constant and an immutable static regex. Every background block already captured locals and hopped to main before mutating anything. The genuine gap was `deinit`, which is what the bounce above closes.

Converting the manager to `@MainActor` was considered and rejected for now: it would be the more rigorous fix, but it forces `async` through the call sites and cannot be validated without a compiler. The contract is documented and enforced where it can actually be violated, which gets the correctness without the unverifiable churn.
