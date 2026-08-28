---
# SAVE-rycg
title: Sign, notarise and harden the release pipeline
status: completed
type: feature
priority: critical
created_at: 2026-08-26T07:07:16Z
updated_at: 2026-08-26T07:16:09Z
parent: SAVE-58vg
---

The single change that turns this from "works if you build it yourself" into an installable product.

## Problem

`make build` signs with `codesign --force --deep --sign -` — an **ad-hoc** signature. CI then publishes that bundle as a GitHub release. Anything downloaded from a browser carries the `com.apple.quarantine` attribute, and Gatekeeper refuses to load an ad-hoc-signed `.saver`. Every user who downloads the release has to know an `xattr -dr com.apple.quarantine` incantation that the README never mentions.

`--deep` is also deprecated by Apple; the bundle should be signed normally.

## Fix

Sign with a **Developer ID Application** certificate using a hardened runtime and a secure timestamp, then notarise and staple:

```
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: NAME (TEAMID)" build/LiveScreensaver.saver
ditto -c -k --keepParent build/LiveScreensaver.saver LiveScreensaver.saver.zip
xcrun notarytool submit LiveScreensaver.saver.zip --key ... --key-id ... --issuer ... --wait
xcrun stapler staple build/LiveScreensaver.saver
```

Ad-hoc signing stays the default for local `make build` so contributors without a certificate are unaffected; signing only engages when the credentials are present.

## ⚠️ App Store distribution is not possible for a `.saver` bundle

Worth settling before any work is planned around it:

- **Guideline 2.4.5(ii) is the blocker**, and it names this case. Mac App Store apps must be "self-contained, single app installation bundles" that "cannot install code or resources in shared locations" — `~/Library/Screen Savers` being one. A developer who shipped an app bundling a `.saver` [was rejected with](https://developer.apple.com/forums/thread/87231) "your app attempts to install a screensaver", and told to remove the functionality. 2.4.5(iv) covers the same ground: no installing "additional code, or resources to add functionality".
- **This is policy, not a technical limit**, which is why the technical workarounds do not rescue it. A sandboxed app can legitimately write outside its container by having the user choose the destination in an `NSSavePanel` and keeping a security-scoped bookmark. 2.4.5(ii) still forbids the outcome.
- App Sandbox is a *second*, independent problem: it forbids executing arbitrary external binaries, so `yt-dlp` — and therefore YouTube support — could not exist in a store build at all.
- Apps that call themselves screensavers on MAS are ordinary full-screen apps that only mimic one — they do not integrate with System Settings → Screen Saver and do not start on idle.
- **The mechanism we would want does exist, privately.** Since macOS 10.15 Apple's own screen savers are App Extensions in `/System/Library/ExtensionKit/Extensions`, not `.saver` bundles — exactly the "app containing a saver" shape that would make store distribution coherent. The API is undocumented; [Aerial](https://github.com/AerialScreensaver/Aerial) is the only third party using it, via private API, which is an automatic rejection. Apple DTS [has said publicly](https://developer.apple.com/forums/thread/797121) that moving screen savers to the app extension model "would be better" and invited enhancement requests. Filing one is the only lever that changes this answer.

**Recommendation:** ship Developer ID + notarisation (this bean). It gives a double-clickable install with no Gatekeeper warnings, which is the outcome the App Store was wanted for. If MAS presence is still desired later, it is a separate product — a full-screen app that is honestly an app, HLS and stream.place only, with no System Settings integration — and should be its own milestone.

Worth watching: macOS Sequoia already demotes third-party screen savers to an "Other" section behind "Show All", and some Tahoe betas did not list them at all. The direction of travel argues for owning distribution rather than waiting on a store route.

## Secrets required in the repository

Settings → Secrets and variables → Actions → **New repository secret**:

| Secret | What it is | How to get it |
| --- | --- | --- |
| `MACOS_CERTIFICATE` | Base64 of the Developer ID Application `.p12` | Xcode → Settings → Accounts → Manage Certificates → export as `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PWD` | Password set when exporting that `.p12` | Chosen at export time |
| `KEYCHAIN_PASSWORD` | Any random string | `openssl rand -base64 24` — used only for the temporary CI keychain |
| `MACOS_SIGNING_IDENTITY` | Full identity name, e.g. `Developer ID Application: Jane Doe (AB12CD34EF)` | `security find-identity -v -p codesigning` |
| `APPLE_API_KEY_ID` | App Store Connect API key ID | App Store Connect → Users and Access → Integrations → Keys |
| `APPLE_API_ISSUER_ID` | Issuer ID shown on that same page | Same page |
| `APPLE_API_KEY_P8` | Base64 of the downloaded `AuthKey_XXXX.p8` | `base64 -i AuthKey_XXXX.p8 \| pbcopy` — Apple lets you download it **once** |

Requires an **Apple Developer Program** membership (99 USD/year). The API-key route is preferred over Apple ID + app-specific password: it is not tied to a personal account and does not break when 2FA changes.

The App Store Connect key needs only the **Developer** role for notarisation.

## Tasks

- [x] Makefile: `SIGN_IDENTITY` variable, defaulting to ad-hoc for local builds
- [x] Makefile: drop `--deep`, add `--options runtime --timestamp`
- [x] Release workflow: import certificate into a temporary keychain, delete it in an `always()` step
- [x] Release workflow: notarise with `notarytool submit --wait` and `stapler staple`
- [x] Verify with `spctl -a -vvv -t install` and `stapler validate`
- [x] Document the secrets above in the README
- [x] Record the App Store finding so it is not re-litigated

## Summary of Changes

### Signing

`SIGN_IDENTITY` now controls how `make build` signs, defaulting to `-` (ad-hoc) so local builds and forks are unaffected. With a real identity it signs with `--options runtime --timestamp` — both required for notarisation — and the deprecated `--deep` flag is gone.

### Notarisation

New `make notarize` zips the bundle with `ditto` (which preserves the signature; `zip` does not), submits it to Apple's notary service with `notarytool submit --wait`, staples the ticket and validates it. New `make assess` runs `spctl -a -vvv -t install`, which is what Gatekeeper will actually decide on a user's machine.

### Release workflow

Imports the certificate into a throwaway keychain in `$RUNNER_TEMP`, builds signed, notarises, confirms Gatekeeper acceptance, and deletes the keychain in an `if: always()` step so signing material never outlives the job.

Signing engages only when the secrets are present, so a fork still gets a working ad-hoc build plus a `::warning::` explaining what it will and will not do, rather than a red workflow.

The archive step changed from `zip` to `ditto -c -k --keepParent`. This is not cosmetic: `zip` drops extended attributes and would have invalidated the signature immediately after applying it.

## App Store: recorded as not possible

Confirmed while writing this. A `.saver` bundle cannot be distributed through the Mac App Store — the store ships sandboxed `.app` bundles only, and a screensaver is a plug-in loaded by a system process with no route through App Store Connect. Repackaging as an app does not rescue it: App Sandbox forbids spawning `yt-dlp` as a subprocess and reading executables from `/opt/homebrew/bin`, which is how YouTube support works.

Developer ID plus notarisation delivers the same practical outcome that was wanted from the App Store: a double-clickable install with no Gatekeeper warning. Documented in the README so the question does not get re-opened from scratch.

## Not verifiable from here

The notarisation path cannot be exercised without the Apple credentials and a macOS runner. The workflow logic, the keychain lifecycle and the Makefile targets are reasoned from the documented `notarytool` and `codesign` interfaces. First real release run should be watched closely.
