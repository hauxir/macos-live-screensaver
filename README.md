# MacOS Live Screensaver

A macOS screensaver that plays live video streams. Supports YouTube videos, [stream.place](https://stream.place) videos, and direct HLS streams.

> **Also available:** [Android TV Live Screensaver](https://github.com/hauxir/androidtv-live-screensaver)

## Why?

Turn any live stream into your screensaver/lockscreen. Some examples:

### [Namib Desert Wildlife](https://www.youtube.com/watch?v=ydYDqZQpim8)
<img width="640" height="360" alt="Image" src="https://github.com/user-attachments/assets/19b39408-8d67-4699-87c9-bb218198190d" />

### [Times Square](https://www.youtube.com/watch?v=rnXIjl_Rzy4)
<img width="640" height="360" alt="Image" src="https://github.com/user-attachments/assets/5db52a77-24a2-4bd1-9698-d3f2258b4890" />

### [The News](https://www.youtube.com/watch?v=iipR5yUp36o)

<img width="640" height="360" alt="Image" src="https://github.com/user-attachments/assets/1d528a72-3d1b-4151-8e9c-347cdfe8d94c" />

## Requirements

- **macOS 13 (Ventura) or later**, Apple Silicon or Intel
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [ffmpeg](https://ffmpeg.org/) — only
  needed for YouTube streams; direct HLS and stream.place URLs work without them

Building from source additionally needs the Swift compiler (Xcode Command Line Tools).

**Disclaimer**: This project was largely vibe-coded — the author had never written Swift
before starting it.

## Installation

### Install (recommended)

1. Download `LiveScreensaver-<version>.zip` from the
   [latest release](https://github.com/jphastings/macos-live-screensaver/releases/latest).
2. Unzip it and double-click `LiveScreensaver.saver`.
3. macOS will offer to install it. Choose whether to install for just you or all users.

Releases are signed with a Developer ID certificate and notarised by Apple, so they open
without a Gatekeeper warning.

<details>
<summary>Seeing "cannot be opened because the developer cannot be verified"?</summary>

That means you have a build that was not notarised — most likely one you built yourself,
or a release from before notarisation was set up. Either build it from source (below), or
download a current release. As a last resort you can clear the quarantine flag yourself:

```bash
xattr -dr com.apple.quarantine ~/Library/Screen\ Savers/LiveScreensaver.saver
```
</details>

### Install yt-dlp and ffmpeg (for YouTube support)

Using Homebrew:
```bash
brew install yt-dlp ffmpeg
```

Or install yt-dlp using pip:
```bash
pip install yt-dlp
brew install ffmpeg
```

### Build from source

```bash
make install
```

Or step by step:
```bash
make build
open build/LiveScreensaver.saver
```

A local build is ad-hoc signed, which is fine on the machine that built it.

Other commands:
```bash
make test       # Run the unit tests
make verify     # Check the built bundle is well-formed
make lint       # Check formatting (needs: brew install swift-format)
make format     # Reformat in place
make clean      # Remove build artefacts
make uninstall  # Remove screensaver from ~/Library/Screen Savers/
make start      # Trigger screensaver immediately
```

Build for a single architecture, or a different minimum OS, by overriding the defaults:

```bash
make build ARCHS=arm64 MACOS_MIN=14.0
```

## Usage

1. Open **System Settings** → **Screen Saver** (**System Preferences** on macOS 12 and
   earlier)
2. Select **Live Screensaver**
3. Click **Options** to configure
4. Enter a video URL:
   - YouTube: `https://www.youtube.com/watch?v=VIDEO_ID` **(live streams only)**
   - HLS stream: `https://example.com/stream.m3u8`
   - stream.place: `https://stream.place/byjp.me`

The settings sheet checks the URL as you type and will not let you save one it cannot
reach, so most mistakes are caught before you leave the sheet.

<img width="526" height="587" alt="Image" src="https://github.com/user-attachments/assets/67d314ff-e17e-43bc-baed-df20c9ece80b" />

Two constraints worth knowing:

- **Only live YouTube videos work.** Regular (non-live) YouTube videos will not play.
- **URLs must be `https://`.** macOS App Transport Security blocks plain `http://`
  connections, so an `http://` stream could never play — earlier versions accepted them
  in the settings sheet and then failed silently at playback.

## Maintainer: release signing

Releases are signed with a **Developer ID Application** certificate and notarised by
Apple, so the screensaver opens without a Gatekeeper warning on machines that have
never seen it. This needs an [Apple Developer Program](https://developer.apple.com/programs/)
membership (99 USD/year).

Signing engages only when the secrets below are present. A fork, or this repo before
the secrets are added, still builds — it just produces an ad-hoc bundle that Gatekeeper
will reject, and the workflow logs a warning saying so.

### Required repository secrets

Add these under **Settings → Secrets and variables → Actions → New repository secret**.

| Secret | What it is | How to get it |
| --- | --- | --- |
| `MACOS_CERT_P12_BASE64` | Base64 of the Developer ID Application `.p12` | Xcode → Settings → Accounts → Manage Certificates → right-click the Developer ID Application cert → Export. Then `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERT_PASSWORD` | The password you set when exporting that `.p12` | Chosen at export time |
| `APPLE_TEAM_ID` | Your 10-character Apple Developer Team ID | Apple Developer → Membership, or the `(...)` suffix from `security find-identity -v -p codesigning` |
| `ASC_KEY_ID` | App Store Connect API key ID | App Store Connect → Users and Access → Integrations → Keys → generate a **Team**-scoped key with the Developer role |
| `ASC_ISSUER_ID` | Issuer ID | Shown at the top of that same Keys page |
| `ASC_PRIVATE_KEY_BASE64` | Base64 of the downloaded `AuthKey_XXXXXXXX.p8` | `base64 -i AuthKey_XXXXXXXX.p8 \| pbcopy` — **Apple only lets you download this once** |

The API-key route is used rather than an Apple ID with an app-specific password: it is
not tied to a personal account, does not break when 2FA settings change, and can be
revoked independently. There's no `KEYCHAIN_PASSWORD` secret — CI generates a random
one for the throwaway signing keychain it creates and deletes within the same job.

These credentials identify the Apple Developer Team, not this app, so they're shared
across every repo signed under it — nothing here is specific to this screensaver.

CI also attests build provenance (`actions/attest-build-provenance`) via keyless
OIDC/Sigstore signing, no secrets required.

### Signing a build locally

```bash
make build SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"

export ASC_KEY_PATH=~/private_keys/AuthKey_XXXXXXXX.p8
export ASC_KEY_ID=XXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
make notarize
make assess     # what Gatekeeper will decide on a user's machine
```

`make build` on its own ad-hoc signs, which is all you need for local testing.

### Cutting a release

Releases are triggered by pushing a tag, not by merging to `main`. The tag *is* the
version — it is stamped into `CFBundleShortVersionString`, so a user can always tell
you exactly which build they are running.

```bash
git tag v1.2.0
git push origin v1.2.0
```

The workflow validates the tag is `vX.Y.Z`, builds and signs it, notarises, and
publishes a release with generated notes and a versioned artefact
(`LiveScreensaver-1.2.0.zip`).

`workflow_dispatch` is available as an escape hatch to re-run a release without moving
a tag — useful if notarisation fails for a transient reason.

### Why not the Mac App Store?

Screen savers cannot be shipped through the Mac App Store, and the obvious workaround —
an app that bundles a `.saver` and installs it — is prohibited by name.

[App Store Review Guideline 2.4.5(ii)](https://developer.apple.com/app-store/review/guidelines/)
requires Mac App Store apps to be "self-contained, single app installation bundles" that
"cannot install code or resources in shared locations". `~/Library/Screen Savers` is such a
location. A developer who tried exactly this
[reported the rejection](https://developer.apple.com/forums/thread/87231): Apple told them
their app "attempts to install a screensaver" and to remove the functionality. 2.4.5(iv)
covers the same ground from the other direction — apps "may not download or install
standalone apps, kexts, additional code, or resources to add functionality".

This is a **policy** limit rather than a technical one, which matters because the technical
workarounds do not help. A sandboxed app *can* legitimately write outside its container by
having the user pick the destination in an `NSSavePanel` and holding a security-scoped
bookmark; 2.4.5(ii) still forbids the result. (Separately, App Sandbox would also block
this screensaver's use of `yt-dlp`, since sandboxed apps may not execute arbitrary external
binaries — so a Mac App Store build could support direct HLS and stream.place only.)

The apps on the store that look like screensavers are standalone full-screen apps that
mimic one. They do not appear in System Settings → Screen Saver and do not start on idle.

#### The mechanism exists, just not for third parties

Since macOS 10.15, Apple's own screen savers are not `.saver` bundles at all — they are
App Extensions in `/System/Library/ExtensionKit/Extensions` (`WallpaperMacintoshExtension.appex`
and friends). That is exactly the "app with a bundled saver" shape that would make store
distribution coherent, but **the API is private and undocumented**. The one third-party
screensaver using it,
[Aerial](https://github.com/AerialScreensaver/Aerial), does so through private API, which is
an automatic App Store rejection.

Apple's own developer support
[has acknowledged the gap](https://developer.apple.com/forums/thread/797121): screen savers
"use the old in-process plug-in model", it "would be better if we updated the API to support
the more sustainable app extension plug-in model", and developers who care are invited to
file an enhancement request. Until that lands, there is no supported route.

**So: Developer ID plus notarisation**, which is what this repository does. It gives a
double-clickable install with no Gatekeeper warning, which is the outcome the App Store was
wanted for in the first place.

## Contributing

```bash
make test    # unit tests for the pure logic in Sources/LiveScreensaverCore
make lint    # formatting (brew install swift-format)
make build   # compile and assemble the bundle
```

Run those three before opening a pull request; CI runs the same checks.

Logic that does not depend on AppKit belongs in `Sources/LiveScreensaverCore/`, which is
the part that can be unit tested. `Screensaver/` holds the AppKit and ScreenSaver layer,
which needs a screensaver host to run at all.

## Troubleshooting

The screensaver tells you what went wrong. When a stream cannot be played you get a
bouncing **Unable to stream** notice with the reason underneath, rather than a black
screen. The table below covers what each reason means.

| On screen | What to do |
| --- | --- |
| `YouTube streams need yt-dlp…` | `brew install yt-dlp ffmpeg` |
| `Found yt-dlp, but other users can modify it…` | The binary is group- or world-writable, so it is not trusted. `chmod go-w` the file, or reinstall it with Homebrew. |
| `The stream is offline or has ended.` | Check the stream is live. Only **live** YouTube videos work; regular videos are not supported. |
| `Couldn't read the stream address for this URL.` | Usually an out-of-date yt-dlp — `brew upgrade yt-dlp`. |
| `That URL doesn't look like a stream.` | Re-check the URL in Options. |
| `The stream kept dropping out.` | The source is having problems; try again later. |
| `No internet connection.` | As it says. |

**A spinner that never resolves** means the stream is still being resolved — YouTube
extraction can take several seconds on first use. If it persists, check the logs below.

**Options button unresponsive**: fixed in recent versions. If you still see it, please
open an issue with the logs below.

### Collecting logs

A screensaver quits the moment you touch the machine, so it cannot be debugged
interactively. It logs to the unified logging system instead. To see what it did:

```bash
log show --predicate 'subsystem == "me.byjp.livescreensaver"' --last 30m --info
```

Or live, while reproducing the problem from another machine or an SSH session:

```bash
log stream --predicate 'subsystem == "me.byjp.livescreensaver"' --info --debug
```

In Console.app, search for `me.byjp.livescreensaver` and enable **Action → Include
Info Messages**.

Stream URLs are logged with their query strings redacted, since those often carry
signed tokens — the output is safe to paste into an issue.
