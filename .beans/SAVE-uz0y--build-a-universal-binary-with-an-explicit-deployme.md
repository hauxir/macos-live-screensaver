---
# SAVE-uz0y
title: Build a universal binary with an explicit deployment target
status: completed
type: task
priority: high
created_at: 2026-08-26T07:06:13Z
updated_at: 2026-08-26T07:14:19Z
parent: SAVE-58vg
---

`swiftc` is invoked in the Makefile with no `-target` flag, so the binary architecture and minimum OS are whatever the build machine happens to be.

In CI that machine is a `macos-latest` runner, which is Apple Silicon. The published artefact is therefore an **arm64-only** dylib with the runner's (very recent) macOS as its implicit deployment target:

- Intel Mac users get a screensaver that silently fails to load.
- Users on an older macOS than the runner may also fail to load it.
- The runner image changing bumps the minimum OS without anyone noticing.

Fix by building both slices explicitly and merging them with `lipo`.

## Tasks

- [x] Add `ARCHS` / `MACOS_MIN` variables to the Makefile
- [x] Compile `arm64-apple-macos<min>` and `x86_64-apple-macos<min>` slices
- [x] `lipo -create` them into the bundle's executable
- [x] Verify with `lipo -info` and `otool -l` in CI that both slices and the expected `LC_BUILD_VERSION` are present
- [x] Pick and document the minimum supported macOS version

## Notes

The README currently says the project was tested only on macOS Tahoe / M2. A CI matrix over runner versions would let us make a real compatibility claim instead.

## Summary of Changes

The build now compiles one slice per architecture with an explicit target triple and merges them with `lipo`:

```
swiftc ... -target arm64-apple-macos13.0  -o build/slices/LiveScreensaver-arm64
swiftc ... -target x86_64-apple-macos13.0 -o build/slices/LiveScreensaver-x86_64
lipo -create -output .../Contents/MacOS/LiveScreensaver build/slices/*
```

Two new Makefile variables control it: `ARCHS` (default `arm64 x86_64`) and `MACOS_MIN` (default `13.0`). Both are overridable, so a contributor who only cares about their own machine can do `make build ARCHS=arm64`.

The repeated `swiftc` invocation is factored into `SWIFT_FLAGS` and `SOURCES` so the flags are stated once for both slices.

`make verify` gained two assertions that turn silent regressions into build failures:

- every architecture in `ARCHS` is actually present in the merged binary (`lipo -archs`)
- `LSMinimumSystemVersion` in the plist matches `MACOS_MIN`

That second check matters because the deployment target and the declared minimum are set in two different files. Previously they could drift with nothing to catch it.

## What this fixes

The published artefact was an **arm64-only** dylib whose minimum OS was whatever SDK the `macos-latest` runner happened to have. Intel Macs got a screensaver that silently failed to load, and a GitHub runner image upgrade would have raised the minimum macOS without anyone noticing.
