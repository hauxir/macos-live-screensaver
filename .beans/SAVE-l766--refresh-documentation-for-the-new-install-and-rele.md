---
# SAVE-l766
title: Refresh documentation for the new install and release story
status: completed
type: task
priority: normal
created_at: 2026-08-26T07:09:14Z
updated_at: 2026-08-26T07:35:59Z
parent: SAVE-61nt
blocked_by:
    - SAVE-rycg
    - SAVE-uz0y
---

The README describes a build-it-yourself project. Once releases are signed, notarised and versioned, the installation story changes completely and the docs need to catch up.

Gaps today:

- No mention of installing from a GitHub release — only `make install` from source.
- No Gatekeeper guidance (moot once notarisation lands, which is the point).
- "Tested exclusively on macOS Tahoe on an M2 MacBook" — replace with the real supported range once the deployment target is set and CI proves it.
- No troubleshooting entry for collecting logs.
- No documentation of the CI secrets or the release process for the maintainer.
- The known System Settings preview bug is described as unexplained; once fixed, that note should go.

## Tasks

- [x] Install-from-release section as the primary path, build-from-source secondary
- [x] State the supported macOS versions and architectures
- [x] Troubleshooting: how to collect logs from Console.app
- [x] Maintainer section: required secrets, how to cut a release
- [x] Remove the preview-bug note once its bean is done
- [x] Add a CONTRIBUTING note covering `make check` before opening a PR

## Summary of Changes

The README described a build-it-yourself project. With releases now signed, notarised and versioned, downloading one is the normal path and the docs say so.

- **Install from a release is now the primary route**, with build-from-source second. A collapsed section explains the Gatekeeper warning for anyone on a self-built or pre-notarisation bundle, including the `xattr` command, rather than leaving them stuck.
- **Requirements state the real supported range** — macOS 13 or later, Apple Silicon *or* Intel — replacing "tested exclusively on macOS Tahoe on an M2 MacBook". yt-dlp and ffmpeg are described as YouTube-only, since direct HLS and stream.place work without them.
- **Troubleshooting rewritten around the on-screen notice.** Every `Unable to stream` reason is in a table with what to do about it, which is more useful than the previous three bullet points now that failures are self-describing.
- **A Contributing section** covering `make test` / `make lint` / `make build` before opening a PR, and where logic belongs — Core for anything testable, `Screensaver/` for the AppKit layer.
- Makefile command list updated with `test`, `verify`, `lint`, `format`, and the `ARCHS` / `MACOS_MIN` overrides.
- **System Preferences → System Settings**, with the old name noted for macOS 12 and earlier.
- The note describing the Options button bug as an unexplained macOS quirk is gone; it is now a one-line troubleshooting entry saying it was fixed.

The "vibe-coded" disclaimer stays — it is honest and useful context for anyone reading the code — reworded only to past tense.

## Correction folded in after review

The `Why not the Mac App Store?` section written in SAVE-rycg led with the sandbox
argument. That was the weaker reason, and it left the obvious follow-up question ("what
about an app that bundles the saver?") looking unexamined.

Rewritten here to lead with App Store Review Guideline 2.4.5(ii) and the rejection
precedent, which address the bundled-app case directly, and to record that Apple's own
screen savers use a private App Extension API that third parties cannot use. The sandbox
point remains as the second, independent obstacle it actually is.

Landed in this bean rather than SAVE-rycg to avoid rewriting nine descendant branches for
a documentation change; the end state after the stack merges is identical.
