---
# SAVE-58vg
title: Distribution & release engineering
status: todo
type: epic
priority: high
created_at: 2026-08-26T07:05:29Z
updated_at: 2026-08-26T07:05:29Z
parent: SAVE-e1qf
---

Everything between "it compiles on my machine" and "a stranger can install it".

Today: `codesign --sign -` (ad-hoc), no notarisation, no `-target` so CI emits an arm64-only dylib pinned to the runner OS, and every push to `main` force-overwrites a single moving `latest` tag with no version number anywhere.

Child beans cover CI PR checks, bundle metadata, universal builds, and the signing/notarisation/App Store pipeline.
