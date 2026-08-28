---
# SAVE-1lr9
title: Replace NSLog with structured os.Logger logging
status: completed
type: task
priority: normal
created_at: 2026-08-26T07:09:14Z
updated_at: 2026-08-26T07:25:42Z
parent: SAVE-61nt
---

A screensaver is the single worst thing to debug interactively: it exits the moment you touch the machine, and it runs inside a system host process you did not launch. Good logging is not a nicety here, it is the only diagnostic channel.

Today there are exactly four `NSLog` calls, all on incidental failures (cache write, lock file attributes, lock file create, yt-dlp exec). Every interesting transition is silent: which URL was chosen, whether the cache hit, whether extraction succeeded, why a retry fired, when the manager gave up.

## Fix

Adopt `os.Logger` with a stable subsystem so a user can be asked for a Console.app excerpt:

```swift
import OSLog
private let log = Logger(subsystem: "me.byjp.livescreensaver", category: "player")
```

Categories: `player`, `extraction`, `config`, `view`.

Log at state transitions, not in `animateOneFrame` — anything on the 30 Hz path must be `.debug` at most, and preferably not there at all.

Use privacy annotations deliberately: stream URLs can contain signed tokens, so log the host and path but redact query strings.

## Tasks

- [x] Replace `NSLog` with `os.Logger`, one logger per category
- [x] Log: chosen source URL, cache hit/miss, extraction start/result/duration, yt-dlp path + version
- [x] Log: player status transitions, each retry with its attempt number and delay, terminal failure
- [x] Redact query strings from logged URLs
- [x] Add a Troubleshooting section to the README telling users how to collect logs

## Summary of Changes

All four `NSLog` calls replaced with `os.Logger` under the subsystem `me.byjp.livescreensaver`, split into three categories: `player`, `extraction` and `config`.

Logging added at every state transition that previously happened silently:

- **player** — setup starting (with the configured URL), player ready, each retry with its attempt number and computed delay, and the terminal give-up with its reason. View register/unregister at `.debug`, so multi-monitor behaviour is legible.
- **extraction** — cache hit vs. miss, the selected yt-dlp path *and version*, extraction duration, and yt-dlp's exit status when it produces no URL.
- **config** — the URL the user saved.

### Privacy

`Log.redact(_:)` strips query strings and fragments before any URL is logged. Extracted stream URLs routinely carry signed tokens and expiry signatures — enough to identify the stream is useful, enough to hand over someone's credentials in a bug report is not. Everything else is marked `.public` explicitly, since `os.Logger` redacts interpolated non-static strings by default and a log full of `<private>` helps nobody.

### yt-dlp version

Resolved once per process by a lazily-initialised global. yt-dlp breaks against YouTube often enough that "which version" is the first useful question about a broken stream, and this means the answer is already in the log rather than something the user has to be asked for.

### Nothing on the hot path

`animateOneFrame` runs 30 times a second per display and gained no logging at all. The only frequently-reachable call sites are `.debug` level.

The README gained a "Collecting logs" section with the `log show` and `log stream` predicates and the Console.app equivalent.
