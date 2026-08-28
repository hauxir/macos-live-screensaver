---
# SAVE-9f13
title: Restructure into a SwiftPM package with unit tests
status: completed
type: task
priority: high
created_at: 2026-08-26T07:09:14Z
updated_at: 2026-08-26T07:34:16Z
parent: SAVE-61nt
---

`screensaver.swift` is a single 1,100-line file containing the player manager, the view, the configuration window controller, a custom tracking view, and the URL helpers. There are no tests, and the Makefile drives `swiftc` directly so there is no test target to run.

This matters most because a good chunk of the logic is **pure and cheaply testable**, and currently a regression in any of it would ship silently:

- `needsYtDlpExtraction(_:)` — decides whether to shell out to yt-dlp at all
- `isStreamPlaceURL(_:)` — host matching, including the `.stream.place` suffix rule
- `getStreamPlaceHLSURL(_:)` — path parsing and the `embed/` prefix strip
- `extractExpirationTimestamp(from:)` — the `expire/([0-9]+)` regex
- cache expiry logic — expiry-in-URL vs. file mtime fallback

## Plan

Convert to a SwiftPM package with two targets:

- `LiveScreensaverCore` — pure logic, no ScreenSaver/AppKit dependency, fully unit tested
- the `.saver` bundle — thin AppKit/ScreenSaver layer that imports Core

Split the remaining AppKit code by type: `SharedPlayerManager.swift`, `LiveScreensaverView.swift`, `ConfigureWindowController.swift`, `ErrorNoticeLayer.swift`.

The Makefile keeps working as the bundle-assembly entry point; `swift test` runs Core's tests and joins the CI checks.

## Tasks

- [x] Add `Package.swift` with a `LiveScreensaverCore` library and a test target
- [x] Move the pure URL/cache helpers into Core
- [x] Write unit tests for each helper, including the awkward cases (embed URLs, trailing slashes, missing expiry, malformed timestamps)
- [x] Split the AppKit code into one file per type
- [x] Update the Makefile to compile Core + bundle sources
- [x] Add `swift test` to CI

## Sequencing

Deliberately scheduled **last** among the code changes: it moves every line in the file, so landing it before the bug fixes would make each of those diffs unreviewable.

## Summary of Changes

`screensaver.swift` (1,100 lines, everything) is now:

```
Sources/LiveScreensaverCore/   pure logic, built and tested by SwiftPM
  Configuration.swift          defaults keys and the default stream
  Logging.swift                os.Logger categories, URL redaction
  StreamURL.swift              stream classification and stream.place mapping
  HLSCachePolicy.swift         cached-URL freshness (new; extracted from the manager)
  StreamError.swift            user-facing failure reasons
  YtDlp.swift                  binary discovery and the safety check
Screensaver/                   AppKit layer, one file per type
  SharedPlayerManager.swift
  LiveScreensaverView.swift
  ConfigureWindowController.swift
Tests/LiveScreensaverCoreTests/
```

### Why Core is a SwiftPM target and the AppKit layer is not

`Screensaver/` sits deliberately outside `Sources/`, so SwiftPM never sees it. It cannot run outside a screensaver host, so a build of it proves nothing that `make build` does not already prove. The Makefile compiles both directories into the single module that becomes the `.saver`, which means the AppKit code needs no `import LiveScreensaverCore` and no cross-module access plumbing, while `swift test` still builds and exercises Core on its own.

The cost is that Core's declarations are `internal` rather than `private`, and the tests use `@testable import`.

### Extracted while splitting

`getCachedHLSURL` mixed file I/O with the freshness decision, so the decision could not be tested. `HLSCachePolicy` now holds the policy — expiry-in-URL beats file age, `now` is injected — and the manager is reduced to reading the file and asking. That collapsed the method from 38 lines to 22 and removed a nested `do/catch` that swallowed all errors identically.

### 31 tests

Covering URL classification, stream.place mapping, cache freshness (both branches, and the precedence between them), log redaction, and the yt-dlp permission check against real temp files with real modes.

`make test` added and wired into CI, so from here a regression in any of this fails a pull request.

## A bug the tests found immediately

`getStreamPlaceHLSURL("https://stream.place/embed/")` returned a playback URL for a user called **"embed"**. The old code trimmed slashes first and then looked for an `"embed/"` prefix — which the trim had just removed. Rewritten to split on `/`, which drops empty segments and so handles trailing slashes, doubled separators and the bare `/embed/` case uniformly.

Worth noting as the argument for the whole bean: that function had been shipping for months, is nine lines long, and reading it did not reveal the bug. Writing the third test case did.
