---
# SAVE-rlb8
title: Distribute via a Homebrew cask
status: todo
type: feature
priority: deferred
created_at: 2026-08-26T07:07:16Z
updated_at: 2026-08-26T07:09:32Z
parent: SAVE-58vg
blocked_by:
    - SAVE-rycg
    - SAVE-lqxy
---

Once releases are signed and notarised, a Homebrew cask is the natural install path — `brew install --cask live-screensaver` beats "clone the repo and run make".

Homebrew supports screen savers as a cask artifact:

```ruby
artifact "LiveScreensaver.saver", target: "~/Library/Screen Savers/LiveScreensaver.saver"
```

## Why this has no PR yet

Submitting to `homebrew/cask` requires the project to meet their notability thresholds, and a personal tap (`jphastings/homebrew-tap`) requires a **separate repository** that cannot be created from within this one. Deferred until the signing and versioned-release beans have landed, since a cask cannot point at a moving `latest` tag and needs a stable checksum per version.

## Tasks

- [ ] Decide: personal tap vs. homebrew/cask submission
- [ ] Create the tap repository if going that route
- [ ] Add a CI step to bump the cask version and sha256 on each release

## Blocked by

Signing/notarisation and versioned releases.
