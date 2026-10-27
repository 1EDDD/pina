# PinaTV Lab experimental tweak

This Theos tweak is a **diagnostic prototype**, not a finished IPA patch.

## What it does

- Targets bundle ID `com.kevin.pinatv`.
- Hooks `AVPlayerItem.setPreferredMaximumResolution:` and asks AVFoundation to prefer 1920x1080.
- Scans loaded Objective-C runtime classes related to resolution, playback, VIP, and ad SDKs, then logs relevant Objective-C-visible selectors.
- Logs modal presentation classes and visible view classes whose names suggest ad presentation.
- Does not transmit logs or media data anywhere; messages go to the device system log.

Runtime introspection only reveals classes/selectors exposed to the Objective-C runtime. Pure Swift methods that are not ObjC-visible will not appear, so missing output does not prove that a feature is absent.

## What it does not do

- It does not unlock VIP, falsify purchase state, or patch the app's VIP checks.
- It does not suppress ads or block ad network requests.
- It cannot make a 1080p rendition exist if the stream only contains 720p, and a resolution preference alone may be ignored by the app's custom player.
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

Install only on a test device in a compatible environment, launch PinaTV, play an episode, and reproduce an ad. Filter the device system log for `PinaTVLabTweak`. The useful signals are:

- `AVPlayerItem max-resolution request`: confirms this playback API was called.
- `Relevant runtime class loaded` and `selectors for`: reveals visible runtime entry points that can be investigated.
- `Modal presentation` and `Observed ad-related view class`: help narrow the UI path for an ad placement.

If the preference is logged but playback remains at 720p, inspect the episode's HLS master playlist and server authorization/configuration. The source may not advertise 1080p, or the app may use another playback path.

## Scope

The purpose of this build is to collect runtime evidence and check compilation. It is not a finished ad-removal, VIP-unlock, or IPA-repackaging solution.
