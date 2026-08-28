---
# SAVE-5e1q
title: Network and subprocess hardening (ATS, HLS check, yt-dlp)
status: completed
type: task
priority: normal
created_at: 2026-08-26T07:08:35Z
updated_at: 2026-08-26T07:30:03Z
parent: SAVE-5ucd
---

Two hardening items around network and subprocess handling.

## 1. `http://` URLs are accepted but will not play

Config validation explicitly allows plain HTTP:

```swift
guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
```

App Transport Security blocks cleartext HTTP by default, so an `http://` URL passes validation with a green tick and then fails silently at playback — the worst possible outcome, because the user has been told it is fine.

Pick one and be deliberate:

- **Preferred:** require `https://` in validation, with a clear message explaining why.
- Or declare a narrow ATS exception in `Info.plist` and document it. A blanket `NSAllowsArbitraryLoads` should be avoided; it weakens every connection the bundle makes and invites review scrutiny.

Validation is also more permissive than playback in a second way: it accepts any URL that returns 2xx to a ranged GET, without checking the response looks like an HLS manifest. Checking for `#EXTM3U` in the first bytes would catch a URL that serves an HTML error page with a 200.

## 2. yt-dlp discovery and execution

```swift
private let ytdlpPaths = [
    "/opt/homebrew/bin/yt-dlp",
    "/usr/local/bin/yt-dlp",
    "/opt/local/bin/yt-dlp",
    (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/yt-dlp"),
]
```

Executing the first match from a fixed list is the right shape — much better than searching `$PATH` — and arguments are passed as an array rather than through a shell, so there is no injection vector from the URL. Two improvements:

- `/usr/local/bin` is world-writable by default on some setups, and `~/.local/bin` is user-writable. A screensaver runs in a system context; verify the binary is owned by root or the current user and is not group/world-writable before executing it.
- Log which `yt-dlp` was selected, and its version, so support questions are answerable.

There is no timeout on the `waitUntilExit()` in `extractHLSURL` — the 15 s `extractionTimeoutSeconds` only governs lock staleness, not the process itself. A hung yt-dlp hangs the extraction thread indefinitely.

## Tasks

- [x] Require HTTPS in validation, or add a documented, narrow ATS exception
- [x] Verify the fetched manifest looks like HLS (`#EXTM3U`), not just 2xx
- [x] Check ownership/permissions of the yt-dlp binary before executing
- [x] Enforce a real timeout on the yt-dlp process and terminate it on expiry
- [x] Log the selected yt-dlp path and version

## Summary of Changes

### HTTPS is now required, rather than accepted and then blocked

Validation accepted `http://` with a green tick, and App Transport Security then blocked it at playback — the worst outcome, because the user had been told it was fine. Plain HTTP is now rejected up front with a message explaining why.

A narrow ATS exception was considered and rejected: it would have to cover arbitrary user-supplied hosts, which means `NSAllowsArbitraryLoads`, weakening every connection the bundle makes. Requiring HTTPS costs almost nothing — YouTube, stream.place and every CDN serving HLS are HTTPS already — and the only real loss is a plain-HTTP stream on a LAN, which is worth trading for not shipping a blanket exception. Documented in the README.

### A 2xx response is no longer taken as proof of a stream

`validateHLSURL` checked only the status code, so a captive portal or a site's custom 404 page answering 200 with HTML passed. It now checks the body begins with `#EXTM3U` — the ranged request already asks for exactly the bytes that would contain it, so this costs nothing extra.

### yt-dlp is checked before it is executed

`isSafeToExecute(_:)` refuses any candidate that is group- or world-writable, or owned by someone other than root or the current user. Two of the four searched locations (`/usr/local/bin`, `~/.local/bin`) are writable without admin rights on a default install, and this process runs in a system context.

A rejected binary is reported distinctly from a missing one — "Found yt-dlp, but other users can modify it, so it wasn't run" rather than "install yt-dlp", which would send someone off to reinstall a binary that is already there.

Argument handling was already correct: arguments go through an array, not a shell, so there was never an injection path from the URL.

### Both yt-dlp invocations now have real timeouts

`extractionTimeoutSeconds` only ever governed how long a *lock file* was considered fresh; nothing bounded the process. A hung yt-dlp hung the extraction thread indefinitely, and in the settings sheet left the spinner going forever with OK disabled.

Both call sites now schedule a `DispatchWorkItem` that terminates the process on expiry, cancelled on normal completion. The sheet reports a termination-by-signal as a timeout rather than a generic "could not load video".

### A latent deadlock fixed on the way past

The extraction path called `waitUntilExit()` and *then* drained the pipe. A child that fills the 64 KB pipe buffer blocks until someone reads it, so that ordering can deadlock — it only worked because `yt-dlp -g` output is short. It now closes the parent's write end and drains before waiting.
