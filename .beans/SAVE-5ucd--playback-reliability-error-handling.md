---
# SAVE-5ucd
title: Playback reliability & error handling
status: todo
type: epic
priority: critical
created_at: 2026-08-26T07:05:30Z
updated_at: 2026-08-26T07:05:30Z
parent: SAVE-e1qf
---

The player state machine in `SharedPlayerManager` and `LiveScreensaverView` has several bugs that strand the user at a black screen or a spinner that never resolves, plus a hard `exit(0)` that kills the process hosting the System Settings preview.

Child beans cover each defect and the new on-screen error presentation.
