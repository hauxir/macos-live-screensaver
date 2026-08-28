---
# SAVE-nsgj
title: Auto Layout and localisation for the configuration sheet
status: todo
type: task
priority: deferred
created_at: 2026-08-26T07:09:14Z
updated_at: 2026-08-26T07:09:14Z
parent: SAVE-61nt
---

`ConfigureWindowController.setupUI()` positions every control with hardcoded frames:

```swift
label.frame = NSRect(x: 20, y: 110, width: 440, height: 20)
urlTextField.frame = NSRect(x: 20, y: 80, width: 440, height: 24)
spinner = NSProgressIndicator(frame: NSRect(x: 438, y: 84, width: 16, height: 16))
```

This works for one fixed-size window in English at the default font size, and breaks with larger accessibility text sizes or any localisation with longer strings. The error messages in the status label are already close to the 440 pt width and will clip.

All user-facing strings are hardcoded English literals; there is no `Localizable.strings`.

## Why this has no PR yet

Genuinely low value at this stage — it affects one window that most users open once. Worth doing before any push for a wider audience, not before the release pipeline and playback bugs are fixed.

## Tasks

- [ ] Convert the configuration sheet to Auto Layout
- [ ] Allow the status label to wrap to two lines
- [ ] Extract user-facing strings into `Localizable.strings`
- [ ] Check layout at the largest accessibility text size
