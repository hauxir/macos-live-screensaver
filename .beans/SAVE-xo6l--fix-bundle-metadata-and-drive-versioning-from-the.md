---
# SAVE-xo6l
title: Fix bundle metadata and drive versioning from the build
status: completed
type: task
priority: high
created_at: 2026-08-26T07:06:13Z
updated_at: 2026-08-26T07:13:13Z
parent: SAVE-58vg
---

`Info.plist` still carries scaffold values that will block an App Store submission and make support impossible.

Current state:

- `CFBundleIdentifier` is `com.livescreensaver.app` — a generic, collision-prone ID that is not tied to a Developer ID/Team. App Store Connect requires an identifier registered to the team.
- `CFBundleShortVersionString` is pinned at `1.0` and `CFBundleVersion` at `1`, so every release ever published claims to be the same version. Users cannot report "broken in X" and there is nothing to roll back to.
- No `LSMinimumSystemVersion`, so macOS has no idea which releases it can load.
- `NSHumanReadableCopyright` is the placeholder `Copyright © 2025. All rights reserved.`

## Tasks

- [x] Change bundle identifier to a reverse-DNS ID owned by the author
- [x] Add `LSMinimumSystemVersion` matching the deployment target
- [x] Set a real copyright string
- [x] Drive `CFBundleShortVersionString` / `CFBundleVersion` from the build (git tag / `VERSION` variable) rather than hardcoding
- [x] Add `NSHighResolutionCapable` and confirm no other keys are required for a `.saver` bundle

## Summary of Changes

`Info.plist` now carries real, shippable metadata:

- `CFBundleIdentifier` changed from the generic `com.livescreensaver.app` to `me.byjp.livescreensaver`, a reverse-DNS identifier the author owns and can register to a developer team.
- `LSMinimumSystemVersion` added, set to **13.0**.
- `NSHighResolutionCapable` added — without it a `.saver` can be composited at 1x on Retina displays.
- Real copyright string, matching the MIT LICENSE.

`CFBundleShortVersionString` and `CFBundleVersion` are now stamped at build time by the Makefile from `VERSION` and `BUILD_NUMBER`, which default to `0.0.0`/`0` so a local build is obviously not a release. `make verify` asserts the stamp actually landed, so a plumbing break fails the build rather than shipping an unversioned bundle.

## The defaults domain was left alone on purpose

`ScreenSaverDefaults(forModuleWithName:)` uses the string constant `ModuleName`, which happened to equal the old bundle identifier. Changing it to match the new one would orphan the stored URL of everyone who already has the screensaver installed. It is unchanged, with a comment in `screensaver.swift` explaining why, so nobody later "tidies up" the mismatch and silently wipes user settings.

## Open question for review

- [ ] Confirm macOS 13.0 is the right floor

13.0 was picked as a defensible lower bound: `CryptoKit`, the AVFoundation APIs and `ScreenSaverView` usage here all predate it comfortably. It has not been *tested* on 13.0 — the README currently only claims macOS Tahoe on an M2. Once the universal-build bean lands, a CI matrix across runner versions can turn this into a verified claim rather than an assumption.
