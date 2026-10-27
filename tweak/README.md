# PinaTV Lab experimental tweak

This Theos tweak is a **diagnostic prototype**, not a finished IPA patch.

## What it does

- Targets bundle ID `com.kevin.pinatv`.
- Hooks `AVPlayerItem.setPreferredMaximumResolution:` and asks AVFoundation to prefer 1920x1080.
- Logs visible view classes whose names suggest ad presentation, to help identify the real runtime ad path.

## What it does not do

- It does not unlock VIP, falsify purchase state, or patch the app's VIP checks.
- It does not suppress ads yet. The static IPA scan identified SDKs and service class names, but not the exact runtime methods used to present each placement. Guessing those methods could crash playback or hide unrelated UI.
- It cannot make a 1080p rendition exist if the stream only contains 720p.
- It has not been compiled or tested on a device in this workspace.

## Build

Requires Theos and an iOS SDK toolchain on a Mac or compatible build host:

```sh
cd tweak
make package
```

Install only on a test device and inspect the device log for `[PinaTVLabTweak]` entries. If the resolution hook logs but playback remains at 720p, inspect the episode's HLS master playlist: the source may not advertise a 1080p rendition, or PinaTV may use a different playback path.

## Next exact step for ad work

Run the app with this diagnostic tweak and capture logs around the moment an ad appears. The concrete runtime class/method path is needed before writing a narrow hook. This avoids blindly disabling SDK methods based only on strings in a compiled binary.
