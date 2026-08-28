---
# SAVE-hrpq
title: Add CI build & lint checks on pull requests
status: completed
type: task
priority: high
created_at: 2026-08-26T07:06:13Z
updated_at: 2026-08-26T07:11:36Z
parent: SAVE-58vg
---

The only workflow in the repo (`.github/workflows/release.yml`) both builds *and* publishes, and only runs on pushes to `main`. Nothing verifies a pull request, and a broken merge to `main` immediately overwrites the `latest` release that users download.

Split verification from publication: a `ci.yml` that builds (and later, tests) on every pull request and on `main`, leaving `release.yml` to do nothing but package and publish.

## Tasks

- [x] Add `.github/workflows/ci.yml` running on `pull_request` and `push` to `main`
- [x] Build the screensaver and assert the bundle structure is intact (binary, Info.plist, thumbnail)
- [x] Add a `swift-format --lint` check with a checked-in `.swift-format` config
- [x] Add a `make lint` / `make check` target so the same checks run locally
- [x] Concurrency group so superseded PR runs are cancelled

## Summary of Changes

Added `.github/workflows/ci.yml` with two jobs, running on every pull request and on pushes to `main`, with a concurrency group that cancels superseded runs.

- **build** — compiles the screensaver and runs `make verify`, a new target asserting the bundle contains its executable, `Info.plist` and thumbnail, that the plist is well-formed, that `NSPrincipalClass` is still `LiveScreensaverView`, and that the signature validates. A silently-broken bundle now fails in CI instead of on a user's machine.
- **format** — installs `swift-format` and runs `make lint` against a checked-in `.swift-format` config (100 columns, 4-space indent, matching the existing style).

`release.yml` now calls `make verify` too, replacing its weaker inline directory check, so the release path and the PR path assert the same things.

## Follow-up: the format job is advisory

The format job is `continue-on-error: true` for now. `screensaver.swift` was not written by a formatter throughout — the spinner path construction around lines 531-539 uses manual continuation alignment that `swift-format` will rewrite — so making the check blocking immediately would put every subsequent PR red on a pre-existing issue.

- [ ] Run `make format` on a macOS machine, commit the result
- [ ] Then replace the advisory step with a plain `run: make lint`

Left undone deliberately rather than guessed at: reformatting 1,100 lines without being able to run the formatter would produce an unreviewable diff.

### What CI actually reported

The advisory job did its job on the first run. Findings, across the tree:

- `LineLength` — the majority, including several lines added by later beans in this stack
- `Spacing` — `size/2` and similar in the spinner path construction, which wants `size / 2`
- `Indentation`, `AddLines`, `RemoveLine`, `TrailingWhitespace` — a handful each

All of it is mechanical; `swift-format format --in-place` resolves the lot.

### Correction: `continue-on-error` was the wrong mechanism

The job was first written with `continue-on-error: true` on the assumption that it would keep the job advisory. It does not. It stops the *workflow run* being marked failed, but the **check run still reports `failure`**, so every pull request in the stack showed a red cross for a job behaving exactly as designed — which is worse than useless, because it trains you to ignore CI.

Replaced with an explicit conditional in the step: run `make lint`, and on findings emit a `::warning::` annotation and print the log, exiting zero. The job now passes, the findings are still visible in the run and as an annotation, and a genuine build failure is the only thing that shows red.
