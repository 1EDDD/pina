# PinaTV Lab experimental tweak

This Theos tweak is a **diagnostic prototype**, not a finished IPA patch.

## What it does

- Targets bundle ID `com.kevin.pinatv`.
- On `AVPlayerItem` initialization, logs only the media URL host and path, omitting query strings/fragments so signed URL tokens are not written to the log.
- Requests a 1920×1080 AVFoundation maximum-resolution preference on `AVPlayerItem` initialization and when the app changes that property.
- Scans loaded Objective-C runtime classes related to resolution, playback, VIP, and ad SDKs, then logs relevant ObjC-visible selectors.
- Logs modal presentation classes and visible view classes whose names suggest ad presentation.
- Does not transmit logs or media data anywhere; messages go to the device system log.

Runtime introspection only reveals classes/selectors exposed to the Objective-C runtime. Pure Swift methods that are not ObjC-visible will not appear, so missing output does not prove that a feature is absent.

## What it does not do

- It does not unlock VIP, falsify purchase state, or patch the app's VIP checks.
- It does not suppress ads or block ad network requests.
- A 1080p preference cannot create a missing 1080p rendition or override a server that supplies only 720p. The app may also use a custom playback path that does not honor AVFoundation's preference.
- The tweak has not yet been verified on a physical device. Check the build workflow before installing anything.

## Build without a Mac

A GitHub Actions workflow is configured at [theos-build.yml](../.github/workflows/theos-build.yml). After that workflow succeeds, download the **PinaTVLabTweak-rootless** artifact from the run's Artifacts section. It contains a rootless jailbreak package, not an IPA.

Manual build with Theos:

```sh
cd tweak
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```

This package requires a compatible rootless jailbreak/tweak-injection environment. It does not install as a normal sideloaded app, and it is not a TrollStore IPA.

## How to collect useful evidence

Install only on a test device in a compatible environment, launch PinaTV, and play an episode. Filter the device system log for `PinaTVLabTweak`. The useful signals are:

- `AVPlayerItem media URL host/path`: shows which player endpoint was given to AVFoundation without revealing query tokens.
- `AVPlayerItem max-resolution request`: confirms the app or tweak touched the maximum-resolution preference.
- `Relevant runtime class loaded` and `selectors for`: reveals visible runtime entry points that can be investigated.
- `Modal presentation` and `Observed ad-related view class`: help narrow the UI path for an ad placement.

If the preference is logged but playback remains at 720p, inspect the actual master playlist and server configuration. The source may not advertise 1080p, or the app may select a restricted media URL before constructing the player item.

## Scope

This build collects runtime evidence and checks compilation. It is not a finished ad-removal, VIP-unlock, or IPA-repackaging solution.
