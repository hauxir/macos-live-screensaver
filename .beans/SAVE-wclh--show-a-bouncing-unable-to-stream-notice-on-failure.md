---
# SAVE-wclh
title: Show a bouncing 'Unable to stream' notice on failure
status: completed
type: feature
priority: high
created_at: 2026-08-26T07:08:01Z
updated_at: 2026-08-26T07:23:59Z
parent: SAVE-5ucd
blocked_by:
    - SAVE-9ndi
---

When a stream fails or a required tool is missing, the user currently gets a black screen and no explanation. `handlePlaybackFailure()` gives up silently after `maxRetries`, and if `yt-dlp` is not installed, `findYtDlpPath()` returns nil and nothing is ever surfaced.

The configuration sheet has good, specific error messages — but they only appear while typing a URL. A stream that dies later, or a `yt-dlp` uninstalled after setup, fails invisibly.

## Design

A notice that bounces around the screen like the DVD logo:

- **"Unable to stream"** in bold
- A user-friendly reason underneath, not bold
- Text wraps so the notice stays near a **16:9 aspect ratio**
- The whole block drifts across the screen, reflecting off the edges

Screensaver-appropriate: no static burn-in, readable at a glance, and the motion makes it obvious the machine is alive rather than crashed.

## Reasons to surface

| Condition | Message underneath |
| --- | --- |
| yt-dlp not found | `YouTube support needs yt-dlp. Install it with: brew install yt-dlp` |
| Stream offline / 404 | `The stream is offline or has ended.` |
| Network unreachable | `No internet connection.` |
| Retries exhausted | `The stream kept dropping out. It may be having problems.` |
| Extraction failed | `Couldn't read the stream address for this URL.` |
| Bad configured URL | `That URL doesn't look like a stream. Check it in Options.` |

## Tasks

- [x] `StreamError` enum with a user-facing reason per case
- [x] `ErrorNoticeLayer`: bold title + regular body, wrapped to ~16:9
- [x] Bounce animation driven from `animateOneFrame`, reflecting off bounds
- [x] Recompute position/scale on resolution change, keep it on-screen on every display
- [x] Route every failure path to a `StreamError` instead of returning silently
- [x] Clear the notice if a retry later succeeds
- [x] Suppress in preview mode

## Summary of Changes

### The notice

"**Unable to stream**" in bold, the reason underneath in regular weight at 62% of the title size and 75% opacity, centred and word-wrapped.

The 16:9 constraint is met by searching for the wrap width rather than guessing one. Height falls as width grows — the same words wrap into fewer lines — so the height-to-width ratio decreases monotonically and a 14-step binary search converges on the width where it crosses 9/16. That keeps the shape right regardless of how long the reason is or what resolution the display runs at.

Font sizes scale with view height, so the notice is proportionate on a laptop panel and a 5K display alike.

### The bounce

`advanceErrorNotice()` runs from `animateOneFrame`, moving the layer by velocity × elapsed time and reflecting off each edge — DVD-logo style. Deliberate details:

- **Time-based, not frame-based**, so the drift speed is the same whatever rate the frame callback actually achieves.
- **Elapsed time capped at 0.1 s**, so a stalled frame cannot teleport the notice across the screen.
- **Implicit CALayer animations disabled** for the move. Without that, Core Animation interpolates every per-frame position change and the motion smears.
- **Randomised start position**, so multiple displays are not in lockstep.
- **Re-wraps on a bounds change**, so a resolution change or a move between screens does not leave the notice mis-sized or stranded off-screen.

### The reasons

`StreamError` maps each failure to something a user can act on, and every silent failure path now routes to one:

| Condition | Shown |
| --- | --- |
| yt-dlp not installed | `YouTube streams need yt-dlp. Install it with: brew install yt-dlp` |
| Extraction returned nothing | `Couldn't read the stream address for this URL.` |
| Unparseable configured URL | `That URL doesn't look like a stream. Check it in Options.` |
| Item failed to load | `The stream is offline or has ended.` |
| Not connected | `No internet connection.` |
| Retry budget spent | `The stream kept dropping out. It may be having problems.` |

A missing `yt-dlp` fails immediately rather than spending the retry budget first — retrying will not conjure up a binary that is not installed.

The notice is suppressed in preview, cleared when a later retry succeeds, and shown to a display that attaches *after* playback has already given up.
