---
# SAVE-fbqi
title: stream.place playback returns 404
status: completed
type: bug
priority: high
created_at: 2026-08-28T21:35:49Z
updated_at: 2026-08-28T21:35:59Z
---

getStreamPlaceHLSURL built a guessed REST path (/api/playback/{user}/hls/index.m3u8) that stream.place's server 404s on. Real API is documented and different.

## Summary of Changes

Reported by JP: `https://stream.place/byjp.me` (his own, definitely-live stream)
showed "Stream not found (HTTP 404)" in the config sheet after the recent PR
stack merged.

**Root cause investigation:** `git blame` on `getStreamPlaceHLSURL` shows the
`/api/playback/{user}/hls/index.m3u8` URL pattern is unchanged since the
original "Handle stream.place URLs" commit — none of the 9 recently-merged
PRs touched this logic, ruling out a regression from that work.

Loaded the real `https://stream.place/byjp.me` page in a real browser and
captured its network traffic: the site's own player never requests that
path. Playback happens over WebRTC (WHEP — SDP offer/answer, ICE, RTP).
Fetching the app's constructed URL directly confirmed a hard 404 straight
from stream.place's server.

stream.place publishes an AT Protocol lexicon reference
(https://stream.place/docs/lex-reference/). Found
`place.stream.playback.getLivePlaylist`: an XRPC query that resolves a
handle to its DID and returns a genuine CMAF `#EXTM3U` HLS playlist.
Verified directly:

```
curl -sD - "https://stream.place/xrpc/place.stream.playback.getLivePlaylist?streamer=byjp.me"
→ HTTP/2 200, content-type: application/vnd.apple.mpegurl, body starts #EXTM3U
```

## Fix

`getStreamPlaceHLSURL` now builds `https://{host}/xrpc/place.stream.playback.getLivePlaylist?streamer={username}`
instead of the guessed REST path. Existing unit tests updated to the
verified URL shape. `swift test` and `make build && make verify` pass
locally.

PR: https://github.com/jphastings/macos-live-screensaver/pull/15
