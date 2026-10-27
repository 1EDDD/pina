# PinaTV Lab

A source-controlled workspace for **static inspection of the supplied IPA** and for validating/selecting HLS resolutions in a player or media source you control.

## Findings from PinaTV 2.0.4

- Bundle ID: `com.kevin.pinatv`; version 2.0.4, build 1; minimum iOS 15.
- Main executable is an ARM64 Mach-O image. The supplied binary reports `cryptid = 0` in its Mach-O encryption metadata, meaning its main executable is not FairPlay-encrypted in this package. This does not mean it is source code or automatically re-signable.
- Relevant code identifiers include `ResolutionSelectorPanel`, `ResolutionOption`, `Vip1080RequiredPromptModifier`, `VIPService`, `TradPlusAdService`, `selectedResolution`, `startResolution`, and `lockPlaybackResolution`.
- API strings include `https://api.pinatv.xyz` and routes under `/vlab/`, including `/vlab/abtest/config`, `/vlab/episode/detail`, and `/vlab/user/app/store/transaction`.
- Resources include TradPlus, Google Mobile Ads, Pangle/TikTok, Unity, Vungle, and other ad-related bundles.
- English and Arabic localization explicitly label 1080p as VIP and say ad-free playback is a membership benefit.

These are **static findings**, not proof of every runtime branch. The IPA alone cannot tell whether your separate private media server supplies a 1080p stream or changes the VIP/config responses.

## HLS auto-1080p player helper

- `Sources/HLSVariantParser.swift`: pure parser for HLS master playlists; recognizes actual variant URLs and resolutions.
- `Sources/HLS1080Selector.swift`: fetches a master playlist and selects an advertised 1080p rendition, with an optional explicit fallback policy.
- `Sources/HLSAutoPlayer.swift`: AVPlayer wrapper that prefers 1080p and starts the episode automatically; if the source lacks 1080p, it selects the best advertised rendition and exposes that fallback state.
- It never upscales 720p content or fabricates a missing 1080p stream.
- These files are for integration into a source project/player you control. They are not injected into the supplied PinaTV executable.

## Inspect the IPA

Run:

```bash
python3 tools/inspect_ipa.py /path/to/PinaTV_2.0.4_decrypted.ipa
# For JSON output:
python3 tools/inspect_ipa.py /path/to/app.ipa --json
```

The tool reads the IPA directly from the ZIP container and does not extract, modify, re-sign, or upload it. A snapshot of the findings is in `docs/ipa-static-report.json`.

## Test

```bash
swift test
```

The HLS parser suite has been run locally: **6 tests passed, 0 failures**. GitHub Actions is configured to run the Swift package tests on macOS for pushes and pull requests.

## Scope / limitations

- This repository does not currently contain PinaTV's original Swift/Xcode source project.
- No modified PinaTV IPA has been produced or tested.
- A real 1080p result requires a 1080p variant in the source playlist, appropriate access rights, and integration into the app's actual playback path.
- Reliable changes to the app's own ad/VIP behavior should be made in source/build configuration or through authorized controls for the service that governs those features.
