---
# SAVE-e1qf
title: Production-ready App Store release
status: todo
type: milestone
priority: high
created_at: 2026-08-26T07:05:14Z
updated_at: 2026-08-26T07:05:14Z
---

Take the screensaver from a vibe-coded prototype that only works when built locally to a signed, notarised product shipped via the Mac App Store.

Three workstreams, tracked as child epics:

1. **Distribution & release engineering** — signing, notarisation, universal binaries, versioned releases. Today's CI publishes an ad-hoc-signed, arm64-only bundle to a moving `latest` tag; Gatekeeper rejects it for anyone who downloads it.
2. **Playback reliability & error handling** — the player state machine has several bugs that produce a black screen or a permanently stuck spinner, with no feedback to the user.
3. **Code quality & maintainability** — one 1,100 line file, no tests, no PR CI, almost no logging.

## Definition of done

- [ ] A tagged release produces a signed + notarised universal `.saver` that installs without Gatekeeper warnings
- [ ] App Store submission requirements understood and blockers documented
- [ ] No known state-machine bug that leaves the user at a black screen or infinite spinner
- [ ] Every stream failure surfaces a human-readable reason on screen
- [ ] PR CI builds and tests the project on every pull request
