---
# SAVE-lqxy
title: Publish versioned, tag-driven releases
status: completed
type: task
priority: high
created_at: 2026-08-26T07:07:16Z
updated_at: 2026-08-26T07:17:18Z
parent: SAVE-58vg
blocked_by:
    - SAVE-xo6l
    - SAVE-rycg
---

`release.yml` triggers on every push to `main` and force-overwrites a single moving tag called `latest`:

```yaml
tag_name: latest
name: Latest Build
```

Consequences:

- There is no version history. A user cannot say "it broke in 1.3" and there is nothing to roll back to.
- Every merge to `main`, including a docs typo fix, republishes the binary users download.
- A broken merge instantly becomes the artefact everyone gets, with no gate in between.

## Fix

Publish on tag pushes (`v*`), not on every `main` push. The tag is the version: strip the leading `v` and stamp it into `CFBundleShortVersionString` at build time, with the build number from the run number or commit count.

## Tasks

- [x] Change the release trigger to `push: tags: ['v*']`
- [x] Derive `VERSION` from the tag and pass it into `make build`
- [x] Generate release notes from commits since the previous tag
- [x] Name the artefact with its version (`LiveScreensaver-1.2.0.zip`)
- [x] Decide whether to keep a rolling `latest` pointer for convenience, or drop it
- [x] Document the release process (tag, push, done) in the README

## Depends on

Version stamping needs the `VERSION` plumbing from the bundle-metadata bean, and a signed release needs the signing bean.

## Summary of Changes

The release workflow now triggers on `push: tags: ['v*']` instead of on every push to `main`.

- The tag is the version. `${GITHUB_REF_NAME#v}` strips the leading `v` and the result is validated against `^[0-9]+\.[0-9]+\.[0-9]+$` before anything is built — a malformed tag fails immediately with a clear message rather than producing a bundle with a nonsense version.
- `VERSION` and `BUILD_NUMBER` (from `github.run_number`) are passed into `make build`, and `make verify` re-checks the stamp landed.
- The release is published at `v<version>` with `generate_release_notes: true`, and the artefact is named `LiveScreensaver-<version>.zip` so a downloaded file stays identifiable long after it leaves the release page.
- `fetch-depth: 0` added, since generated release notes need the previous tag.
- `workflow_dispatch` with a version input, as an escape hatch to re-run a release without moving a tag — worth having because notarisation can fail transiently.

The README maintainer section documents the process: tag, push, done.

## Note on the existing `latest` release

The old workflow force-overwrote a tag called `latest` on every push to `main`. This workflow no longer touches it, so the existing `latest` release will freeze at whatever it currently points to rather than disappearing.

- [ ] Decide whether to delete the stale `latest` release, or keep it as a rolling pointer

Left as a judgement call rather than deleting anything: any README, blog post or bookmark pointing at the `latest` download URL would break. Now that releases are versioned, the honest options are to delete it, or to add a step that also updates `latest` to mirror the newest tag.
