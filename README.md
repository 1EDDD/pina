# PinaTV Lab

A source-controlled workspace for static inspection of the supplied PinaTV IPA, HLS variant selection, and a narrowly scoped diagnostic injection experiment.

## Findings from PinaTV 2.0.4

- Bundle ID: `com.kevin.pinatv`; version 2.0.4, build 1; minimum iOS 15.
- The executable is a 64-bit ARM Mach-O image and has `cryptid = 0` in its Mach-O encryption metadata. This does not mean it is source code or automatically re-signable.
- Playback/quality identifiers include `ResolutionSelectorPanel`, `ResolutionOption`, `Vip1080RequiredPromptModifier`, `VIPService`, `selectedResolution`, `startResolution`, and `lockPlaybackResolution`.
- Ad-related identifiers include `TradPlusAdService`, `BannerAdLoader`, `BannerAdManager`, and splash-ad handlers.
- API strings include `https://api.pinatv.xyz` and routes under `/vlab/`.
- English and Arabic localization describe 1080p as VIP-exclusive and ad-free playback as a membership benefit.

These are static findings, not proof of every runtime branch. The IPA alone cannot establish whether a separate private media server controls app configuration, VIP state, or the playlist actually passed to the player.

## Experimental standalone diagnostic dylib

`injected/Injected.m` is a standalone library that does not depend on MobileSubstrate. It targets only `com.kevin.pinatv`, requests AVFoundation's 1920×1080 maximum-resolution preference, and writes sanitized media URL host/path details to `Documents/PinaTVLab.log`. Query strings are omitted because they may contain signed tokens.

After a successful GitHub Actions run, download the **PinaTVLabInjected-dylib** artifact. The `tools/inject_dylib.py` utility can embed it in a decrypted copy of this app:

```bash
python3 tools/inject_dylib.py \
  /path/to/PinaTV_2.0.4_decrypted.ipa \
  /path/to/PinaTVLabInjected.dylib \
  /path/to/PinaTV_diagnostic.ipa \
  --enable-file-sharing
```

The script adds an `LC_LOAD_DYLIB` command and places the library in `Frameworks`. The output is **not signed for installation**; it must be re-signed by a legitimate sideloading tool before use. With file sharing enabled, the app's Documents folder is exposed so the log can be retrieved in Files.

This experiment only requests an actual 1080p rendition and collects diagnostics. It does **not** change VIP/purchase checks, unlock paid features, or suppress ads. A player preference cannot create a 1080p source or override a server that returns only 720p. Use a test copy and expect that unsupported injection or signing workflows can cause the app not to launch.

A separate rootless jailbreak package is also built by the workflow as **PinaTVLabTweak-rootless**. It requires a compatible tweak-injection environment and is not a normal sideloaded IPA.

## HLS auto-1080p player helper

- `Sources/HLSVariantParser.swift` parses HLS master playlists and resolves relative rendition URLs.
- `Sources/HLS1080Selector.swift` chooses a genuine advertised 1080p variant or applies an explicit fallback policy.
- `Sources/HLSAutoPlayer.swift` starts playback automatically and exposes the selected resolution/fallback state.

These files are for integration into a media client and streams you control or are authorized to access. They are not injected into the original app.

## Inspect and test

```bash
python3 tools/inspect_ipa.py /path/to/PinaTV_2.0.4_decrypted.ipa
swift test
python3 -m unittest discover -s tests -v
```

The static IPA inspector reads the ZIP container and does not patch binaries. GitHub Actions runs the Swift suite, tests the Mach-O injection utility, and builds the diagnostic binaries.

## Limitations

- The original PinaTV Swift/Xcode project is not present.
- No VIP or ad behavior has been patched.
- A real 1080p result requires the source playlist to advertise 1080p and the app's actual playback path to honor the AVFoundation preference.
- The standalone dylib and IPA injection are experimental and require successful build, re-signing, installation, and on-device validation.
